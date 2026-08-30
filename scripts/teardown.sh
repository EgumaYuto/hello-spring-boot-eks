#!/usr/bin/env bash
#
# Tear everything down in the reverse order it was created.
#
# The ALB is created by the controller (not Terraform), so we MUST delete the
# Ingress first and let the controller remove the ALB. Otherwise the orphaned
# ALB and its security groups block the VPC/subnet destroy in the platform layer.
#
# Usage:
#   AWS_PROFILE=sandbox-eks ./scripts/teardown.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_DIR="infra/application/aws"
NAMESPACE="$(terraform -chdir="$APP_DIR" output -raw namespace 2>/dev/null || echo hello-spring-boot-eks)"

echo "==> [1/5] Deleting the Ingress (removes the ALB) and app resources"
kubectl delete -f k8s/ingress.yaml --ignore-not-found
# Give the controller time to delete the ALB before we remove its IAM role.
sleep 30
kubectl delete -f k8s/service.yaml --ignore-not-found
kubectl delete deployment hello-spring-boot-eks -n "$NAMESPACE" --ignore-not-found
kubectl delete secret db -n "$NAMESPACE" --ignore-not-found
kubectl delete -f k8s/namespace.yaml --ignore-not-found

echo "==> [2/5] Uninstalling the AWS Load Balancer Controller"
helm uninstall aws-load-balancer-controller -n kube-system || true

echo "==> [3/5] Destroying the application layer (EKS, Aurora, IAM)"
terraform -chdir="$APP_DIR" destroy

echo "==> [4/5] Destroying the platform layer (VPC, subnets, ECR)"
echo "    NOTE: ECR must be empty or the destroy fails; delete images first if needed."
terraform -chdir=infra/platform/aws destroy

echo "==> [5/5] Done."
