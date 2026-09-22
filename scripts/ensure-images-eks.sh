#!/bin/bash
# Garante que as imagens customizadas referenciadas em apps/eks/ e
# charts/*-eks/ existem no ECR. Para cada imagem: le a tag JA fixada no
# manifest correspondente; se essa tag ja existir no ECR, pula (nao
# builda de novo); se nao existir, builda a partir do codigo atual e
# faz push com essa mesma tag.
#
# Escopo deliberadamente limitado (ver SPEC-015): nao gera tag nova por
# Git SHA nem atualiza manifests. Isso e' responsabilidade do SPEC-016
# (CI/CD), ainda nao implementado. Este script serve para bootstrap de
# uma conta/regiao nova onde o ECR ainda esta vazio.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

AWS_REGION="${AWS_REGION:-us-east-2}"
# Mesma conta hardcoded em todo o resto do repo (charts, apps, k8s-eks).
# code/airflow-dags/build.sh tambem usa esse valor fixo — nao deriva
# via aws sts para nao divergir do que build.sh gera localmente.
ECR_REGISTRY="${ECR_REGISTRY:-093499160510.dkr.ecr.${AWS_REGION}.amazonaws.com}"

echo "==> Login no ECR (${ECR_REGISTRY})..."
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY" >/dev/null

image_exists() {
  local repo="$1" tag="$2"
  aws ecr describe-images --region "$AWS_REGION" \
    --repository-name "data-platform/${repo}" \
    --image-ids "imageTag=${tag}" >/dev/null 2>&1
}

# --- airflow-dags (inclui o projeto dbt embutido) ---
AIRFLOW_TAG=$(grep -A1 "repository:.*airflow-dags" apps/eks/airflow-app.yaml \
  | grep "tag:" | head -1 | awk '{print $2}')
if [ -z "$AIRFLOW_TAG" ]; then
  echo "ERRO: nao consegui extrair a tag de airflow-dags de apps/eks/airflow-app.yaml" >&2
  exit 1
fi
echo "==> airflow-dags:${AIRFLOW_TAG}"
if image_exists airflow-dags "$AIRFLOW_TAG"; then
  echo "    ja existe no ECR, pulando build."
else
  echo "    nao encontrada, buildando e publicando..."
  bash code/airflow-dags/build.sh "$AIRFLOW_TAG"
  docker push "${ECR_REGISTRY}/data-platform/airflow-dags:${AIRFLOW_TAG}"
fi

# --- api-service ---
API_TAG=$(grep -oP '(?<=data-platform/api-service:)[A-Za-z0-9.\-]+' \
  code/api-service/k8s-eks/kustomization.yaml | head -1)
if [ -z "$API_TAG" ]; then
  echo "ERRO: nao consegui extrair a tag de api-service de code/api-service/k8s-eks/kustomization.yaml" >&2
  exit 1
fi
echo "==> api-service:${API_TAG}"
if image_exists api-service "$API_TAG"; then
  echo "    ja existe no ECR, pulando build."
else
  echo "    nao encontrada, buildando e publicando..."
  docker build -t "${ECR_REGISTRY}/data-platform/api-service:${API_TAG}" code/api-service
  docker push "${ECR_REGISTRY}/data-platform/api-service:${API_TAG}"
fi

# --- metabase (imagem base + driver Trino) ---
METABASE_TAG=$(grep -oP '(?<=data-platform/metabase:)[A-Za-z0-9.\-]+' \
  charts/metabase-eks/metabase.yaml | head -1)
if [ -z "$METABASE_TAG" ]; then
  echo "ERRO: nao consegui extrair a tag de metabase de charts/metabase-eks/metabase.yaml" >&2
  exit 1
fi
echo "==> metabase:${METABASE_TAG}"
if image_exists metabase "$METABASE_TAG"; then
  echo "    ja existe no ECR, pulando build."
else
  echo "    nao encontrada, buildando e publicando..."
  docker build -t "${ECR_REGISTRY}/data-platform/metabase:${METABASE_TAG}" code/metabase
  docker push "${ECR_REGISTRY}/data-platform/metabase:${METABASE_TAG}"
fi

echo "==> Imagens customizadas OK."
