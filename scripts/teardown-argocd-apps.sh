#!/bin/bash
# Remove todas as Applications do ArgoCD de forma segura ANTES do
# terraform destroy. Sem isso, o terraform apagaria a VPC/cluster com
# NLBs e volumes EBS ainda vivos (criados pelos Services/PVCs), que
# ficam orfaos na conta AWS — ja aconteceu uma vez nesta sessao.
#
# Adiciona o finalizer de cascade em toda Application antes de deletar,
# para o ArgoCD podar (prune) os recursos reais (Services, PVCs, Jobs,
# Deployments...) de cada uma antes de remove-la de verdade.
set -euo pipefail

TIMEOUT_SECONDS="${1:-600}"

KUBECTL="kubectl"
if [ -n "${KUBE_CONTEXT:-}" ]; then KUBECTL="kubectl --context=${KUBE_CONTEXT}"; fi

if ! $KUBECTL get namespace argocd >/dev/null 2>&1; then
  echo "Namespace argocd nao existe, nada a remover."
  exit 0
fi

apps=$($KUBECTL get applications -n argocd -o name 2>/dev/null || true)
if [ -z "$apps" ]; then
  echo "Nenhuma Application do ArgoCD encontrada."
  exit 0
fi

echo "==> Marcando $(echo "$apps" | wc -l) Application(s) para cascade delete..."
for a in $apps; do
  $KUBECTL patch "$a" -n argocd --type merge \
    -p '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}' >/dev/null
done

echo "==> Deletando (isso poda NLBs, PVCs/EBS, Jobs etc. de cada app)..."
$KUBECTL delete applications -n argocd --all --wait=true --timeout="${TIMEOUT_SECONDS}s"

echo "==> Conferindo que nao sobrou nenhuma Application..."
remaining=$($KUBECTL get applications -n argocd -o name 2>/dev/null || true)
if [ -n "$remaining" ]; then
  echo "AVISO: ainda ha Applications presas (finalizer travado?):" >&2
  echo "$remaining" >&2
  echo "Verifique manualmente antes de rodar terraform destroy." >&2
  exit 1
fi

echo "==> Todas as Applications removidas. Confira manualmente antes do terraform destroy:"
echo "    aws elbv2 describe-load-balancers --region \${AWS_REGION:-us-east-2} --query 'LoadBalancers[].LoadBalancerName'"
echo "    aws ec2 describe-volumes --region \${AWS_REGION:-us-east-2} --filters Name=status,Values=available --query 'Volumes[].VolumeId'"
