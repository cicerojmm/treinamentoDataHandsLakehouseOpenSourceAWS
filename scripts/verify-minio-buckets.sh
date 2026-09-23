#!/bin/bash
# Confere se os buckets definidos em charts/minio-eks-setup/kustomization.yaml
# existem no MinIO do EKS. Uso: verify-minio-buckets.sh [timeout_s]
set -euo pipefail

TIMEOUT_SECONDS="${1:-300}"
KUBECTL="kubectl"
if [ -n "${KUBE_CONTEXT:-}" ]; then KUBECTL="kubectl --context=${KUBE_CONTEXT}"; fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
expected=$(grep -oP '(?<=- buckets=).*' "$ROOT_DIR/charts/minio-eks-setup/kustomization.yaml")
if [ -z "$expected" ]; then
  echo "ERRO: lista de buckets nao encontrada em charts/minio-eks-setup/kustomization.yaml" >&2
  exit 1
fi

elapsed=0
while true; do
  existing=$($KUBECTL exec -n data-platform minio-eks-pool-0-0 -c minio -- sh -c \
    'mc alias set v http://localhost:9000 minio minio123 >/dev/null 2>&1 && mc ls v/' 2>/dev/null \
    | awk '{print $NF}' | tr -d '/' || true)
  missing=""
  for b in $expected; do
    echo "$existing" | grep -qx "$b" || missing="$missing $b"
  done
  if [ -z "$missing" ]; then
    echo "Buckets do MinIO OK: $expected"
    exit 0
  fi
  if [ "$elapsed" -ge "$TIMEOUT_SECONDS" ]; then
    echo "ERRO: buckets ausentes no MinIO:$missing" >&2
    echo "O Job minio-create-buckets (Application minio-eks-setup) nao rodou ou falhou." >&2
    echo "Verifique: $KUBECTL get application minio-eks-setup -n argocd -o jsonpath='{.status.operationState}'" >&2
    exit 1
  fi
  echo "[${elapsed}s] aguardando buckets:$missing"
  sleep 10
  elapsed=$((elapsed + 10))
done
