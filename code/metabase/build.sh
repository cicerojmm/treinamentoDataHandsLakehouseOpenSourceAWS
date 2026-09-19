#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="093499160510.dkr.ecr.us-east-2.amazonaws.com/data-platform/metabase"
TAG=${1:-"v$(date +%Y%m%d%H%M%S)"}

echo "=== Build: $TAG ==="

# Login ECR
aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin 093499160510.dkr.ecr.us-east-2.amazonaws.com

# Build
docker build -t "$REPO:$TAG" "$SCRIPT_DIR"

# Push
docker push "$REPO:$TAG"

echo "Done! Image: $REPO:$TAG"
echo "TAG=$TAG"
