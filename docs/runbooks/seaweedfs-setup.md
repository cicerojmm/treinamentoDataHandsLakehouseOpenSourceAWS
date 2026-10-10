# SeaweedFS (SPEC-018)

Object storage S3-compatível que roda **em paralelo ao MinIO** (namespace
`data-platform`, local e EKS). A migração dos consumidores é incremental; o
MinIO só sai quando tudo estiver migrado.

## Endpoints

| | MinIO (AIStor) | SeaweedFS |
|---|---|---|
| S3 (EKS) | `http://minio-eks-hl.data-platform.svc.cluster.local:9000` | `http://seaweedfs-s3.data-platform.svc.cluster.local:8333` |
| S3 (local) | `http://minio-local-hl.data-platform.svc.cluster.local:9000` | `http://seaweedfs-s3.data-platform.svc.cluster.local:8333` |
| Buckets | bronze, warehouse, silver, gold, airbyte-storage | bronze, warehouse |

> Os buckets `bronze` e `warehouse` existem **nos dois** storages com o mesmo
> nome. O que diferencia é o endpoint e a credencial — confira sempre o
> `--endpoint-url` antes de gravar. Acesso sempre *path-style*.

Componentes: `seaweedfs-master` (9333), `seaweedfs-volume` (8080),
`seaweedfs-filer` (8888, metadados em leveldb2 no PVC) e `seaweedfs-s3` (8333,
Deployment dedicado).

## Acesso

```bash
CTX=data-platform-eks   # ou o contexto do kind
kubectl --context=$CTX port-forward -n data-platform svc/seaweedfs-s3 8333:8333

AK=$(kubectl --context=$CTX get secret seaweedfs-s3-secret -n data-platform -o jsonpath='{.data.admin_access_key_id}' | base64 -d)
SK=$(kubectl --context=$CTX get secret seaweedfs-s3-secret -n data-platform -o jsonpath='{.data.admin_secret_access_key}' | base64 -d)
AWS_ACCESS_KEY_ID=$AK AWS_SECRET_ACCESS_KEY=$SK AWS_DEFAULT_REGION=us-east-1 \
  aws --endpoint-url http://localhost:8333 s3 ls
```

UIs: `svc/seaweedfs-filer 8888:8888` e `svc/seaweedfs-master 9333:9333`.

## Credenciais
Estáticas no Git (ambiente de testes, mesmo tratamento do MinIO): em
`apps/{local,eks}/seaweedfs-app.yaml` (`s3.credentials`) e no Job de
`charts/seaweedfs-{local,eks}-setup/`. Distintas das do MinIO e entre
ambientes. Para trocar, altere nos dois lugares do mesmo ambiente.

## Verificação
```bash
KUBE_CONTEXT=data-platform-eks bash scripts/verify-seaweedfs-buckets.sh 60
```

## Troubleshooting
- PVC `Pending`: `kubectl get sc` (local `standard`, EKS `gp3`) e `kubectl describe pvc`.
- Job `seaweedfs-create-buckets` falhando: `kubectl logs -n data-platform job/seaweedfs-create-buckets`; o initContainer espera `seaweedfs-s3:8333`.
- `ImagePullBackOff`: imagem `chrislusf/seaweedfs:4.48` vem do Docker Hub (rate limit) — espelhar no ECR é spec futuro.

## Conexão Airbyte → SeaweedFS (bronze/movielens)
Cria source, destination (SeaweedFS) e connection (`movies`, `ratings`,
`links`, `tags`; sempre `full_refresh_overwrite`, Parquet/SNAPPY, manual) via
API pública do Airbyte. Idempotente (reaproveita o que já existe pelo nome):
```bash
KUBE_CONTEXT=data-platform-eks bash scripts/airbyte-seaweedfs-connection.sh --sync
```
Destino: `s3://bronze/movielens/<tabela>/` **no SeaweedFS** (a conexão para o
MinIO, descrita em `airbyte-eks-setup.md`, continua existindo à parte).
Pré-requisitos: Apps `seaweedfs`, `seaweedfs-setup`, `airbyte` e
`postgres-all` Synced/Healthy.
