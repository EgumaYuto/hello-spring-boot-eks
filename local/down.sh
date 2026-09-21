#!/usr/bin/env bash
#
# Delete the local kind cluster (frees all local resources; no AWS involved).
#
#   ./local/down.sh
set -euo pipefail

CLUSTER="hello-spring-boot"

echo "==> Deleting kind cluster (${CLUSTER})"
kind delete cluster --name "$CLUSTER"
echo "==> Done."
