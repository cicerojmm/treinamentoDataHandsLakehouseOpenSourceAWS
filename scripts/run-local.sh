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
#   1. verifica os pre-requisitos (docker, kind, kubectl, helm, aws, git);
#      se faltar algum, roda scripts/ec2-bootstrap.sh para instalar
#   2. git pull (atualiza para o que estiver em origin/main)
#   3. cria o cluster kind se nao existir (reaproveita se ja existir)
#   4. aplica os namespaces
#   5. instala/atualiza o aistor-objectstore-operator (exige o Secret
#      minio-local-license, criado manualmente antes — ver instrucoes
#      no proprio script se faltar)
#   6. cria o ecr-pull-secret (token do ECR, expira em 12h)
#   7. instala/atualiza o ArgoCD
#   8. aplica o app-of-apps (aponta para apps/local/) e espera todas as
#      Applications ficarem Synced/Healthy
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

CLUSTER_NAME="data-platform-local"
KIND_CONFIG="infra/clusters/local/kind-config.yaml"

TOTAL_STEPS=8
REQUIRED_BINS=(git docker kind kubectl helm aws)

missing_bins() {
  local m=()
  for bin in "${REQUIRED_BINS[@]}"; do
    command -v "$bin" >/dev/null 2>&1 || m+=("$bin")
  done
  echo "${m[*]:-}"
}

echo "==> [1/${TOTAL_STEPS}] Verificando pre-requisitos (${REQUIRED_BINS[*]})..."
MISSING="$(missing_bins)"
if [ -n "$MISSING" ]; then
  echo "    faltando: ${MISSING}"
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "ERRO: instalacao automatica so' suporta Ubuntu/Debian (apt-get). Instale manualmente: ${MISSING}" >&2
    exit 1
  fi
  echo "    rodando scripts/ec2-bootstrap.sh para instalar..."
  bash "$SCRIPT_DIR/ec2-bootstrap.sh"
  MISSING="$(missing_bins)"
  if [ -n "$MISSING" ]; then
    echo "ERRO: continua faltando apos o ec2-bootstrap: ${MISSING}" >&2
    exit 1
  fi
fi
if ! docker info >/dev/null 2>&1; then
  echo "ERRO: docker nao esta acessivel (daemon parado ou usuario fora do grupo docker)." >&2
  echo "Se o docker acabou de ser instalado, faca logout/login (ou 'newgrp docker') e rode de novo." >&2
  exit 1
fi

echo "==> [2/${TOTAL_STEPS}] git pull..."
git pull --ff-only

echo "==> [3/${TOTAL_STEPS}] Cluster kind '${CLUSTER_NAME}'..."
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "    ja existe, reaproveitando."
else
  echo "    criando..."
  kind create cluster --config "$KIND_CONFIG"
fi

echo "==> [4/${TOTAL_STEPS}] Aplicando namespaces..."
kubectl apply -f bootstrap/namespaces.yaml

# MinIO Inc. trancou pull anonimo das imagens legadas (quay.io/minio/minio,
# Docker Hub) em 2026-09; o caminho publico atual e' quay.io/minio/aistor,
# que exige licenca (gratuita p/ single-node, via subnet.min.io). A licenca
# fica so' no Secret do cluster, nunca commitada — precisa existir antes
# deste passo.
echo "==> [5/${TOTAL_STEPS}] Instalando/atualizando aistor-objectstore-operator..."
bash bootstrap/minio-aistor-operator/ensure-license-secret.sh minio-local-license data-platform
helm repo add minio-helm https://helm.min.io/ >/dev/null 2>&1 || true
helm repo update minio-helm >/dev/null
helm upgrade --install aistor-objectstore-operator minio-helm/aistor-objectstore-operator \
  --namespace data-platform \
  -f bootstrap/minio-aistor-operator/install-values.yaml \
  --set license="$(kubectl get secret minio-local-license -n data-platform -o jsonpath='{.data.minio\.license}' | base64 -d)" \
  --wait

# Imagens customizadas vem do ECR privado; nodes do kind nao tem IAM role,
# entao o pull precisa de imagePullSecret (usa as credenciais AWS locais).
echo "==> [6/${TOTAL_STEPS}] Criando ecr-pull-secret..."
bash bootstrap/ecr-auth/local-ecr-secret.sh

echo "==> [7/${TOTAL_STEPS}] Instalando/atualizando ArgoCD..."
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update >/dev/null
if helm status argocd -n argocd >/dev/null 2>&1; then
  helm upgrade argocd argo/argo-cd -n argocd -f bootstrap/argocd/install-values-local.yaml --wait
else
  helm install argocd argo/argo-cd -n argocd --create-namespace -f bootstrap/argocd/install-values-local.yaml --wait
fi
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

echo "==> [8/${TOTAL_STEPS}] Aplicando app-of-apps e aguardando ficar tudo Synced/Healthy..."
kubectl apply -f apps/local/app-of-apps.yaml
# numero de Applications esperado = arquivos de Application em apps/local/
# (inclui o proprio app-of-apps); derivado dos arquivos pra nao ficar defasado
EXPECTED_APPS="$(grep -l '^kind: Application$' apps/local/*.yaml | wc -l)"
bash scripts/wait-argocd-healthy.sh 1800 15 "$EXPECTED_APPS"

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
echo "  kubectl port-forward -n orchestration svc/airflow-api-server 8080:8080"
echo ""
echo "Se estiver numa maquina remota (EC2), abra um tunel SSH para essas"
echo "portas em vez de expor no Security Group, ex:"
echo "  ssh -L 8080:localhost:8080 -L 8001:localhost:8001 usuario@<ip-da-maquina>"
echo ""
