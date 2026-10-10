#!/bin/bash
# Confere se os buckets definidos em charts/seaweedfs-eks-setup/kustomization.yaml
# existem no SeaweedFS do EKS. Uso: verify-seaweedfs-buckets.sh [timeout_s]
#
# Credenciais lidas do Secret seaweedfs-s3-secret (gerado pelo chart a partir
# de s3.credentials). Roda um pod efemero com amazon/aws-cli, mesma imagem do
# Job de criacao dos buckets.
set -euo pipefail

TIMEOUT_SECONDS="${1:-300}"
KUBECTL="kubectl"
if [ -n "${KUBE_CONTEXT:-}" ]; then KUBECTL="kubectl --context=${KUBE_CONTEXT}"; fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP_DIR="${SETUP_DIR:-charts/seaweedfs-eks-setup}"
expected=$(grep -oP '(?<=- buckets=).*' "$ROOT_DIR/$SETUP_DIR/kustomization.yaml")
if [ -z "$expected" ]; then
  echo "ERRO: lista de buckets nao encontrada em $SETUP_DIR/kustomization.yaml" >&2
  exit 1
fi

elapsed=0
while true; do
  ACCESS_KEY=$($KUBECTL get secret seaweedfs-s3-secret -n data-platform -o jsonpath='{.data.admin_access_key_id}' 2>/dev/null | base64 -d || true)
  SECRET_KEY=$($KUBECTL get secret seaweedfs-s3-secret -n data-platform -o jsonpath='{.data.admin_secret_access_key}' 2>/dev/null | base64 -d || true)
  existing=""
  if [ -n "$ACCESS_KEY" ] && [ -n "$SECRET_KEY" ]; then
    $KUBECTL delete pod verify-seaweedfs-buckets -n data-platform --ignore-not-found --grace-period=0 >/dev/null 2>&1 || true
    existing=$($KUBECTL run verify-seaweedfs-buckets -n data-platform --restart=Never --rm -i --quiet \
      --image=amazon/aws-cli:2.17.40 \
      --overrides="{\"spec\":{\"containers\":[{\"name\":\"verify-seaweedfs-buckets\",\"image\":\"amazon/aws-cli:2.17.40\",\"command\":[\"aws\",\"--endpoint-url\",\"http://seaweedfs-s3.data-platform.svc.cluster.local:8333\",\"s3\",\"ls\"],\"env\":[{\"name\":\"AWS_ACCESS_KEY_ID\",\"value\":\"${ACCESS_KEY}\"},{\"name\":\"AWS_SECRET_ACCESS_KEY\",\"value\":\"${SECRET_KEY}\"},{\"name\":\"AWS_DEFAULT_REGION\",\"value\":\"us-east-1\"}]}]}}" \
      2>/dev/null | awk '{print $NF}' || true)
  fi
  missing=""
  for b in $expected; do
    echo "$existing" | grep -qx "$b" || missing="$missing $b"
  done
  if [ -z "$missing" ]; then
    echo "Buckets do SeaweedFS OK: $expected"
    exit 0
  fi
  if [ "$elapsed" -ge "$TIMEOUT_SECONDS" ]; then
    echo "ERRO: buckets ausentes no SeaweedFS:$missing" >&2
    echo "Verifique: $KUBECTL get application seaweedfs seaweedfs-setup -n argocd" >&2
    exit 1
  fi
  echo "[${elapsed}s] aguardando buckets:$missing"
  sleep 10
  elapsed=$((elapsed + 10))
done
