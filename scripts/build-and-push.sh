#!/usr/bin/env bash
#
# Build the Spring Boot jar, package it into a Docker image, and push it to ECR.
#
# Usage:
#   AWS_PROFILE=sandbox-eks ./scripts/build-and-push.sh [image_tag]
#
# The jOOQ sources are committed under src/main/generated, so the build does not
# need a local MySQL. If you change the DB schema, regenerate them first with a
# local MySQL (see README) — that is the only time you need docker compose here.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

IMAGE_TAG="${1:-latest}"

ECR_URL="$(terraform -chdir=infra/platform/aws output -raw ecr_repository_url)"
REGISTRY="${ECR_URL%/*}"        # <account>.dkr.ecr.<region>.amazonaws.com
REGION="$(echo "$REGISTRY" | cut -d. -f4)"

echo "==> Building jar (skipping jOOQ regeneration; using committed sources)"
./gradlew clean bootJar -x generateHellodbJooq -x test

echo "==> Building image ${ECR_URL}:${IMAGE_TAG}"
# EKS Fargate nodes are linux/amd64; build for that platform explicitly so this
# works from Apple Silicon too.
docker build --platform linux/amd64 -t "${ECR_URL}:${IMAGE_TAG}" .

echo "==> Logging in to ECR (${REGISTRY})"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

echo "==> Pushing ${ECR_URL}:${IMAGE_TAG}"
docker push "${ECR_URL}:${IMAGE_TAG}"

echo "==> Done: ${ECR_URL}:${IMAGE_TAG}"
