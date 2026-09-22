#!/bin/bash
# Executa (ou atualiza) a plataforma completa localmente via kind.
#
# Funciona igual em qualquer maquina — notebook, EC2, qualquer lugar —
# desde que o repositorio ja esteja clonado ali e as dependencias
# (docker, kind, kubectl, helm) instaladas. Numa EC2 Ubuntu nova, rode
# antes: bash scripts/ec2-bootstrap.sh
#
# Uso:
#   bash scripts/run-local.sh
#
# O que faz, em ordem:
#   1. git pull (atualiza para o que estiver em origin/main)
#   2. cria o cluster kind se nao existir (reaproveita se ja existir)
#   3. aplica os namespaces
#   4. instala/atualiza o ArgoCD
#   5. aplica o app-of-apps (aponta para apps/local/)
#   6. espera todas as Applications ficarem Synced/Healthy
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

CLUSTER_NAME="data-platform-local"
KIND_CONFIG="infra/clusters/local/kind-config.yaml"

echo "==> [1/6] git pull..."
git pull --ff-only

echo "==> [2/6] Verificando pre-requisitos (docker, kind, kubectl, helm)..."
for bin in docker kind kubectl helm; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "ERRO: '$bin' nao encontrado no PATH." >&2
    echo "Numa maquina Ubuntu nova (ex: EC2), rode antes: bash scripts/ec2-bootstrap.sh" >&2
    exit 1
  fi
done
docker info >/dev/null 2>&1 || { echo "ERRO: docker nao esta rodando (ou seu usuario nao esta no grupo docker)." >&2; exit 1; }

echo "==> [3/6] Cluster kind '${CLUSTER_NAME}'..."
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "    ja existe, reaproveitando."
else
  echo "    criando..."
  kind create cluster --config "$KIND_CONFIG"
fi

echo "==> [4/6] Aplicando namespaces..."
kubectl apply -f bootstrap/namespaces.yaml

echo "==> [5/6] Instalando/atualizando ArgoCD..."
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update >/dev/null
if helm status argocd -n argocd >/dev/null 2>&1; then
  helm upgrade argocd argo/argo-cd -n argocd -f bootstrap/argocd/install-values-local.yaml --wait
else
  helm install argocd argo/argo-cd -n argocd --create-namespace -f bootstrap/argocd/install-values-local.yaml --wait
fi
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

echo "==> [6/6] Aplicando app-of-apps e aguardando ficar tudo Synced/Healthy..."
kubectl apply -f bootstrap/argocd/app-of-apps.yaml
# 13 = numero de Applications esperado em apps/local/ (ajuste se adicionar novas)
bash scripts/wait-argocd-healthy.sh 1800 15 13

echo ""
echo "=========================================="
echo "Plataforma local no ar!"
echo "=========================================="
echo ""
echo "ArgoCD:  http://localhost:8080   (usuario admin, senha: make argocd-password)"
echo "Airbyte: http://localhost:8001"
echo ""
echo "As demais UIs (Airflow, Metabase, Trino, Grafana, OpenMetadata) nao"
echo "tem porta mapeada no kind-config.yaml — acesse via port-forward, ex:"
echo "  kubectl port-forward -n ingestion svc/airflow-api-server 8080:8080"
echo ""
echo "Se estiver numa maquina remota (EC2), abra um tunel SSH para essas"
echo "portas em vez de expor no Security Group, ex:"
echo "  ssh -L 8080:localhost:8080 -L 8001:localhost:8001 usuario@<ip-da-maquina>"
echo ""
