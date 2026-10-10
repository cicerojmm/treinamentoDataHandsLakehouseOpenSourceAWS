#!/bin/bash
# Cria (idempotente) no Airbyte, via API publica, a conexao
#   sample-source-postgres (movielens) --> SeaweedFS s3://bronze/movielens/<tabela>/
# sempre Full refresh | Overwrite, Parquet/SNAPPY, schedule manual.
#
# Uso: airbyte-seaweedfs-connection.sh [--sync]
#   --sync   dispara um sync ao final e espera terminar (succeeded/failed)
# Env: KUBE_CONTEXT (default: contexto atual), LOCAL_PORT (default 18001)
#
# Credenciais nunca vem do Git: SeaweedFS le de seaweedfs-s3-secret
# (data-platform) e o Postgres de sample-source-postgres-secret (ingestion).
# Requer curl e python3 (sem jq).
set -euo pipefail

KUBECTL="kubectl"
if [ -n "${KUBE_CONTEXT:-}" ]; then KUBECTL="kubectl --context=${KUBE_CONTEXT}"; fi
PORT="${LOCAL_PORT:-18001}"
API="http://localhost:${PORT}/api/public/v1"
STREAMS="movies ratings links tags"
SRC_NAME="sample-postgres-movielens"
DST_NAME="seaweedfs-bronze"
CONN_NAME="sample-postgres-to-seaweedfs-bronze"
S3_ENDPOINT="http://seaweedfs-s3.data-platform.svc.cluster.local:8333"
DO_SYNC=false; [ "${1:-}" = "--sync" ] && DO_SYNC=true

for c in curl python3; do command -v $c >/dev/null || { echo "ERRO: $c nao encontrado" >&2; exit 1; }; done

secret() { $KUBECTL get secret "$1" -n "$2" -o jsonpath="{.data.$3}" | base64 -d; }

SW_AK=$(secret seaweedfs-s3-secret data-platform admin_access_key_id)
SW_SK=$(secret seaweedfs-s3-secret data-platform admin_secret_access_key)
PG_USER=$(secret sample-source-postgres-secret ingestion POSTGRES_USER)
PG_PASS=$(secret sample-source-postgres-secret ingestion POSTGRES_PASSWORD)
PG_DB=$(secret sample-source-postgres-secret ingestion POSTGRES_DB)
[ -n "$SW_AK" ] && [ -n "$SW_SK" ] || { echo "ERRO: credenciais do SeaweedFS nao encontradas" >&2; exit 1; }

echo "==> port-forward airbyte-server -> localhost:${PORT}"
$KUBECTL port-forward -n ingestion svc/airbyte-airbyte-server-svc "${PORT}:8001" >/dev/null 2>&1 &
PF=$!; trap 'kill $PF 2>/dev/null || true' EXIT
for i in $(seq 1 30); do curl -fs "$API/workspaces" >/dev/null 2>&1 && break; sleep 2; done

api() { curl -fsS -H 'Content-Type: application/json' "$@"; }
# py '<expr sobre d>' le JSON do stdin e imprime a expressao
py() { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)"; }

WS=$(api "$API/workspaces" | py "d['data'][0]['workspaceId']")
echo "workspace: $WS"

find_id() { # $1=resource $2=name $3=idfield
  api "$API/$1?workspaceIds=$WS" | NAME="$2" FIELD="$3" python3 -c "
import sys,json,os
d=json.load(sys.stdin)
print(next((x[os.environ['FIELD']] for x in d.get('data',[]) if x['name']==os.environ['NAME']),''))"
}

# --- Source ---
SRC_ID=$(find_id sources "$SRC_NAME" sourceId)
if [ -z "$SRC_ID" ]; then
  BODY=$(WS="$WS" N="$SRC_NAME" U="$PG_USER" P="$PG_PASS" DB="$PG_DB" python3 -c "
import json,os
e=os.environ
print(json.dumps({'name':e['N'],'workspaceId':e['WS'],'configuration':{
 'sourceType':'postgres','host':'sample-source-postgres.ingestion.svc.cluster.local','port':5432,
 'database':e['DB'],'schemas':['public'],'username':e['U'],'password':e['P'],
 'ssl_mode':{'mode':'disable'},'tunnel_method':{'tunnel_method':'NO_TUNNEL'},
 'replication_method':{'method':'Standard'}}}))")
  SRC_ID=$(api -X POST "$API/sources" -d "$BODY" | py "d['sourceId']")
  echo "source criado: $SRC_ID"
else echo "source ja existe: $SRC_ID"; fi

# --- Destination (SeaweedFS) ---
DST_ID=$(find_id destinations "$DST_NAME" destinationId)
if [ -z "$DST_ID" ]; then
  BODY=$(WS="$WS" N="$DST_NAME" EP="$S3_ENDPOINT" AK="$SW_AK" SK="$SW_SK" python3 -c "
import json,os
e=os.environ
print(json.dumps({'name':e['N'],'workspaceId':e['WS'],'configuration':{
 'destinationType':'s3','s3_endpoint':e['EP'],'s3_bucket_name':'bronze','s3_bucket_path':'movielens',
 's3_bucket_region':'us-east-1','access_key_id':e['AK'],'secret_access_key':e['SK'],
 's3_path_format':'\${STREAM_NAME}/\${YEAR}_\${MONTH}_\${DAY}_\${EPOCH}_',
 'format':{'format_type':'Parquet','compression_codec':'SNAPPY'}}}))")
  DST_ID=$(api -X POST "$API/destinations" -d "$BODY" | py "d['destinationId']")
  echo "destination criado: $DST_ID"
else echo "destination ja existe: $DST_ID"; fi

# --- Connection ---
CONN_ID=$(find_id connections "$CONN_NAME" connectionId)
if [ -z "$CONN_ID" ]; then
  BODY=$(N="$CONN_NAME" S="$SRC_ID" D="$DST_ID" STREAMS="$STREAMS" python3 -c "
import json,os
e=os.environ
print(json.dumps({'name':e['N'],'sourceId':e['S'],'destinationId':e['D'],
 'schedule':{'scheduleType':'manual'},
 'configurations':{'streams':[{'name':s,'syncMode':'full_refresh_overwrite'} for s in e['STREAMS'].split()]}}))")
  CONN_ID=$(api -X POST "$API/connections" -d "$BODY" | py "d['connectionId']")
  echo "connection criada: $CONN_ID"
else echo "connection ja existe: $CONN_ID"; fi

if $DO_SYNC; then
  JOB=$(api -X POST "$API/jobs" -d "{\"connectionId\":\"$CONN_ID\",\"jobType\":\"sync\"}" | py "d['jobId']")
  echo "sync disparado: job $JOB"
  for i in $(seq 1 90); do
    st=$(api "$API/jobs/$JOB" | py "d['status']")
    echo "[$((i*10))s] status: $st"
    case "$st" in succeeded) echo "OK"; exit 0;; failed|cancelled) echo "ERRO: job $st" >&2; exit 1;; esac
    sleep 10
  done
  echo "ERRO: timeout aguardando o job" >&2; exit 1
fi
