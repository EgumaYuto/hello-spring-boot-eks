#!/usr/bin/env bash
#
# Spin up the whole app on a local kind cluster — zero AWS cost.
#
#   ./local/up.sh
#
# Requires: docker, kind, kubectl (no AWS credentials needed).
# The same app image and Kubernetes primitives as the EKS version; only the
# edges differ (nginx Ingress instead of ALB, in-cluster MySQL instead of Aurora,
# a static Secret instead of Secrets Manager).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CLUSTER="hello-spring-boot"
IMAGE="hello-spring-boot:local"
NGINX_VERSION="controller-v1.11.2"
NS="hello-spring-boot"

echo "==> [1/6] Creating kind cluster (${CLUSTER})"
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "    already exists — reusing"
else
  kind create cluster --config local/kind-config.yaml
fi

echo "==> [2/6] Installing the nginx Ingress controller"
kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/${NGINX_VERSION}/deploy/static/provider/kind/deploy.yaml"
echo "    waiting for the controller to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s

echo "==> [3/6] Building the app image (local arch, using committed jOOQ sources)"
./gradlew clean bootJar -x generateHellodbJooq -x test
docker build -t "$IMAGE" .

echo "==> [4/6] Loading the image into kind"
kind load docker-image "$IMAGE" --name "$CLUSTER"

echo "==> [5/6] Applying manifests"
kubectl apply -f local/manifests/namespace.yaml
kubectl apply -f local/manifests/

echo "==> [6/6] Waiting for MySQL and the app to be ready"
kubectl rollout status deployment/mysql -n "$NS" --timeout=180s
kubectl rollout status deployment/hello-spring-boot -n "$NS" --timeout=240s

echo ""
echo "    Ready:  http://localhost/"
echo "    Try:    curl http://localhost/      (expect: Hello World!)"
echo "    Logs:   kubectl logs -n ${NS} deploy/hello-spring-boot -f"
echo "    Stop:   ./local/down.sh"
