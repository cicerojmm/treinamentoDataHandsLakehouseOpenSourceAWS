# Runbook: Conexão Airbyte no EKS (sample source → bronze)

Configuração manual (decisão D3 do SPEC-015). Refazer sempre que o cluster
EKS for recriado — o estado do Airbyte fica no Postgres dedicado.

## Pré-requisitos
- Apps `airbyte`, `postgres-all` e `minio-eks-setup` Synced/Healthy
- Bucket `bronze` criado (Job `minio-create-buckets`)
- Sample source com dados Movielens (carregados via initdb no primeiro start)
- Storage interno do Airbyte apontando pro MinIO da plataforma
  (`storage.type: minio` em `apps/eks/airbyte-app.yaml` — sem passo
  manual). Conferir:
  ```bash
  kubectl get configmap airbyte-airbyte-env -n ingestion \
    -o jsonpath='{.data.STORAGE_TYPE} {.data.MINIO_ENDPOINT} {.data.S3_PATH_STYLE_ACCESS}'
  # esperado: minio http://minio-eks-hl.data-platform.svc.cluster.local:9000 true
  ```

```bash
kubectl exec -n ingestion deploy/sample-source-postgres -- \
  psql -U sample -d movielens -c "SELECT count(*) FROM movies;"
```

## 1. Acessar a UI
```bash
kubectl get svc -n ingestion airbyte-airbyte-webapp-svc \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
# http://<hostname>:8001
```

## 2. Source — Postgres
| Campo | Valor |
|---|---|
| Host | `sample-source-postgres.ingestion.svc.cluster.local` |
| Port | `5432` |
| Database | `movielens` |
| Schemas | `public` |
| User / Password | `sample` / `sample123` |
| SSL mode | `disable` |
| Update method | `Scan Changes with User Defined Cursor` |

## 3. Destination — S3 (MinIO)
| Campo | Valor |
|---|---|
| S3 Bucket Name | `bronze` |
| S3 Bucket Path | `movielens` |
| S3 Bucket Region | `us-east-1` |
| S3 Endpoint | `http://minio-eks-hl.data-platform.svc.cluster.local:9000` |
| Access Key / Secret | `minio` / `minio123` |
| Output Format | `Parquet: Columnar Storage` |
| S3 Path Format | `${NAMESPACE}/${STREAM_NAME}/` → usar `${STREAM_NAME}/` |

O caminho final precisa ser `s3://bronze/movielens/<tabela>/`, que é o
`external_location` usado pela DAG `dbt_movielens`.

## 4. Connection
- Streams: `movies`, `ratings`, `links`, `tags` — modo `Full refresh | Overwrite`
- Schedule: `Manual`
- Rodar **Sync now**

## 5. Verificação
```bash
kubectl run mc --rm -it --restart=Never -n data-platform \
  --image=quay.io/minio/mc:RELEASE.2024-11-21T17-21-54Z -- \
  sh -c "mc alias set m http://minio-eks-hl:9000 minio minio123 && mc ls -r m/bronze/movielens"
```
Esperado: arquivos `.parquet` em `movies/`, `ratings/`, `links/`, `tags/`.

Em seguida, disparar a DAG `dbt_movielens` no Airflow.
