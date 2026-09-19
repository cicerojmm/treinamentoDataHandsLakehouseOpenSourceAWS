#!/bin/bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-2}"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

NAMESPACES=("data-platform" "orchestration" "ingestion")

echo "==> Obtendo token ECR..."
ECR_TOKEN=$(aws ecr get-login-password --region "${AWS_REGION}")

for NS in "${NAMESPACES[@]}"; do
  echo "==> Criando/atualizando secret ecr-pull-secret no namespace ${NS}..."

  kubectl delete secret ecr-pull-secret -n "${NS}" 2>/dev/null || true

  kubectl create secret docker-registry ecr-pull-secret \
    --docker-server="${ECR_REGISTRY}" \
    --docker-username=AWS \
    --docker-password="${ECR_TOKEN}" \
    -n "${NS}"
done

echo ""
echo "Secrets criados com sucesso!"
echo "Lembre-se: o token expira em 12h. Re-execute este script ou use o CronJob."
