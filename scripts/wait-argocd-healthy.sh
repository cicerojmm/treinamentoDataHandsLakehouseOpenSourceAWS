#!/bin/bash
# Aguarda todas as Applications do ArgoCD (namespace argocd) ficarem
# Synced + Healthy, imprimindo o progresso a cada checagem. Falha com
# exit 1 se o timeout for atingido.
set -euo pipefail

TIMEOUT_SECONDS="${1:-1800}"   # default 30 min
POLL_SECONDS="${2:-15}"
MIN_APPS="${3:-1}"             # numero minimo de Applications esperado

KUBECTL="kubectl"
if [ -n "${KUBE_CONTEXT:-}" ]; then KUBECTL="kubectl --context=${KUBE_CONTEXT}"; fi

elapsed=0
while true; do
  apps_json=$($KUBECTL get applications -n argocd -o json)
  total=$(echo "$apps_json" | python3 -c "import json,sys;print(len(json.load(sys.stdin)['items']))")

  if [ "$total" -lt "$MIN_APPS" ]; then
    echo "[${elapsed}s] aguardando o ArgoCD descobrir as Applications (${total}/${MIN_APPS})..."
  else
    not_ready=$(echo "$apps_json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
bad = []
for a in d['items']:
    name = a['metadata']['name']
    sync = a.get('status', {}).get('sync', {}).get('status', '?')
    health = a.get('status', {}).get('health', {}).get('status', '?')
    if sync != 'Synced' or health != 'Healthy':
        bad.append(f'{name}={sync}/{health}')
print('\n'.join(bad))
")
    if [ -z "$not_ready" ]; then
      echo "[${elapsed}s] Todas as ${total} Applications estao Synced/Healthy."
      exit 0
    fi
    echo "[${elapsed}s] aguardando (${total} apps):"
    echo "$not_ready" | sed 's/^/    /'
  fi

  if [ "$elapsed" -ge "$TIMEOUT_SECONDS" ]; then
    echo "TIMEOUT apos ${TIMEOUT_SECONDS}s esperando as Applications ficarem Synced/Healthy." >&2
    echo "Verifique manualmente: $KUBECTL get applications -n argocd" >&2
    exit 1
  fi

  sleep "$POLL_SECONDS"
  elapsed=$((elapsed + POLL_SECONDS))
done
