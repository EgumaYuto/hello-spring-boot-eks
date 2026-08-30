#!/usr/bin/env bash
#
# Configure the cluster and deploy the app. Run AFTER:
#   1. terraform apply in infra/platform/aws
#   2. terraform apply in infra/application/aws
#   3. ./scripts/build-and-push.sh <image_tag>
#
# Usage:
#   AWS_PROFILE=sandbox-eks ./scripts/deploy.sh [image_tag]
#
# Requires: aws, kubectl, helm, jq.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

IMAGE_TAG="${1:-latest}"
APP_DIR="infra/application/aws"

tf() { terraform -chdir="$APP_DIR" output -raw "$1"; }

CLUSTER_NAME="$(tf cluster_name)"
REGION="$(tf region)"
VPC_ID="$(tf vpc_id)"
ECR_URL="$(tf ecr_repository_url)"
NAMESPACE="$(tf namespace)"
ALB_ROLE_ARN="$(tf alb_controller_role_arn)"
DB_SECRET_ARN="$(tf db_secret_arn)"
IMAGE="${ECR_URL}:${IMAGE_TAG}"

echo "==> [1/6] Updating kubeconfig for ${CLUSTER_NAME}"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"

echo "==> [2/6] Making CoreDNS run on Fargate"
# The default CoreDNS deployment is annotated for EC2 nodes; remove that so the
# pods can be scheduled onto Fargate, then restart them.
kubectl patch deployment coredns -n kube-system --type=json \
  -p='[{"op":"remove","path":"/spec/template/metadata/annotations/eks.amazonaws.com~1compute-type"}]' \
  2>/dev/null || echo "    (compute-type annotation already removed)"
kubectl rollout restart deployment coredns -n kube-system
kubectl rollout status deployment coredns -n kube-system --timeout=300s

echo "==> [3/6] Installing the AWS Load Balancer Controller (Helm)"
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo update eks >/dev/null
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set region="$REGION" \
  --set vpcId="$VPC_ID" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=$ALB_ROLE_ARN" \
  --wait --timeout=600s

echo "==> [4/6] Creating the namespace and DB Secret"
kubectl apply -f k8s/namespace.yaml

SECRET_JSON="$(aws secretsmanager get-secret-value --secret-id "$DB_SECRET_ARN" \
  --region "$REGION" --query SecretString --output text)"
DB_HOST="$(echo "$SECRET_JSON" | jq -r .host)"
DB_PORT="$(echo "$SECRET_JSON" | jq -r .port)"
DB_NAME="$(echo "$SECRET_JSON" | jq -r .dbname)"
DB_USER="$(echo "$SECRET_JSON" | jq -r .username)"
DB_PASS="$(echo "$SECRET_JSON" | jq -r .password)"
DB_URL="jdbc:mysql://${DB_HOST}:${DB_PORT}/${DB_NAME}"

kubectl create secret generic db -n "$NAMESPACE" \
  --from-literal=SPRING_DATASOURCE_URL="$DB_URL" \
  --from-literal=SPRING_DATASOURCE_USERNAME="$DB_USER" \
  --from-literal=SPRING_DATASOURCE_PASSWORD="$DB_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> [5/6] Deploying the app (image: ${IMAGE})"
sed "s|\${IMAGE}|${IMAGE}|g" k8s/deployment.yaml | kubectl apply -f -
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml
kubectl rollout status deployment/hello-spring-boot-eks -n "$NAMESPACE" --timeout=300s

echo "==> [6/6] Waiting for the ALB address (provisioned by the controller)"
for i in $(seq 1 40); do
  ADDR="$(kubectl get ingress hello-spring-boot-eks -n "$NAMESPACE" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  if [ -n "$ADDR" ]; then
    echo ""
    echo "    App URL: http://${ADDR}/"
    echo "    (the ALB may take a minute or two more to pass health checks)"
    exit 0
  fi
  sleep 15
done

echo "    ALB address not ready yet. Check later with:"
echo "    kubectl get ingress hello-spring-boot-eks -n ${NAMESPACE}"
