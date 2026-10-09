# Runbook: Conexão Airbyte (sample source → bronze)

Configuração manual (decisão D3 do SPEC-015). Refazer sempre que o cluster
for recriado — o estado do Airbyte fica no Postgres dedicado, então um
cluster novo volta sem source, destination nem connection.

Vale para o EKS e para o local (kind); as diferenças estão em
[Local x EKS](#local-x-eks).

## Pré-requisitos
- Apps `airbyte`, `postgres-all` e `minio-eks-setup` Synced/Healthy
- Bucket `bronze` criado (Job `minio-create-buckets`)
- Sample source Postgres no ar (`sample-source-postgres`, namespace
  `ingestion`). O seed do repo tem só **200 linhas** (50 filmes); para o
  dataset completo, ver [Dataset completo](#opcional-dataset-completo-movielens)
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
Nesta instalação o Airbyte **não tem login** (autenticação desligada): quem
tiver a URL do LoadBalancer consegue alterar conectores.

## 2. Source — Postgres
| Campo | Valor |
|---|---|
| Host | `sample-source-postgres.ingestion.svc.cluster.local` |
| Port | `5432` |
| Database | `movielens` |
| Schemas | `public` |
| User / Password | `sample` / `sample123` (secret `sample-source-postgres-secret`) |
| SSL mode | `disable` |
| Update method | `Scan Changes with User Defined Cursor` (na API: `replication_method.method = Standard`) |

Como todas as tabelas rodam em Full refresh, o cursor não é usado.

## 3. Destination — S3 (MinIO)
As credenciais do MinIO foram rotacionadas e **não** são mais
`minio`/`minio123`. Leia do secret do cluster (não cole em lugar nenhum):
```bash
kubectl get secret airbyte-storage-secret -n ingestion -o jsonpath='{.data.s3-access-key-id}' | base64 -d; echo
kubectl get secret airbyte-storage-secret -n ingestion -o jsonpath='{.data.s3-secret-access-key}' | base64 -d; echo
```

| Campo | Valor |
|---|---|
| S3 Bucket Name | `bronze` |
| S3 Bucket Path | `movielens` |
| S3 Bucket Region | `us-east-1` |
| S3 Endpoint | `http://minio-eks-hl.data-platform.svc.cluster.local:9000` |
| Access Key / Secret | as duas chaves do secret acima |
| Output Format | `Parquet: Columnar Storage` (compressão `SNAPPY`) |
| S3 Path Format | `${STREAM_NAME}/${YEAR}_${MONTH}_${DAY}_${EPOCH}_` |

O caminho final precisa ser `s3://bronze/movielens/<tabela>/`, que é o
`external_location` usado pela DAG `dbt_movielens`. **Não** deixe o
`${NAMESPACE}/` no path format, senão os arquivos vão para
`movielens/public/<tabela>/` e as external tables ficam vazias.

## 4. Connection
- Streams: `movies`, `ratings`, `links`, `tags` — modo `Full refresh | Overwrite`
- Schedule: `Manual`
- Rodar **Sync now**

Overwrite validado: a cada sync os arquivos anteriores da tabela são
removidos e substituídos (o número no nome do arquivo é o epoch do sync),
sem duplicar linhas.

## 5. Verificação
Lista os arquivos do bucket com um pod efêmero do `aws-cli` (o `mc` exige
login no registry e não é mais usado nos runbooks):
```bash
AK=$(kubectl get secret airbyte-storage-secret -n ingestion -o jsonpath='{.data.s3-access-key-id}' | base64 -d)
SK=$(kubectl get secret airbyte-storage-secret -n ingestion -o jsonpath='{.data.s3-secret-access-key}' | base64 -d)
kubectl run awscli-check --rm -i --restart=Never -n data-platform --image=amazon/aws-cli \
  --env AWS_ACCESS_KEY_ID="$AK" --env AWS_SECRET_ACCESS_KEY="$SK" --env AWS_DEFAULT_REGION=us-east-1 -- \
  --endpoint-url http://minio-eks-hl.data-platform.svc.cluster.local:9000 \
  s3 ls --recursive s3://bronze/movielens/
```
Esperado: arquivos `.parquet` em `movies/`, `ratings/`, `links/`, `tags/`, e
a soma das linhas igual à do Postgres (com o dataset completo:
9.742 filmes, 100.836 ratings, 9.742 links, 3.683 tags).

Em seguida, disparar a DAG `dbt_movielens` no Airflow.

## Alternativa: criar via API (sem UI)
Com autenticação desligada, a API pública funciona direto. Em outro
terminal: `kubectl port-forward -n ingestion svc/airbyte-airbyte-server-svc 18001:8001`.
A base é `http://localhost:18001/api/public/v1` e a ordem é:

1. `GET /workspaces` → `workspaceId`.
2. `POST /sources` com `configuration.sourceType = "postgres"`, os campos da
   seção 2 e `replication_method = {"method": "Standard"}`,
   `tunnel_method = {"tunnel_method": "NO_TUNNEL"}`, `ssl_mode = {"mode": "disable"}`.
3. `POST /destinations` com `configuration.destinationType = "s3"`, os campos
   da seção 3 (`s3_endpoint`, `s3_bucket_name`, `s3_bucket_path`,
   `s3_path_format`, `access_key_id`, `secret_access_key`) e
   `format = {"format_type": "Parquet", "compression_codec": "SNAPPY"}`.
4. `POST /connections` com `schedule = {"scheduleType": "manual"}` e, em
   `configurations.streams`, `{"name": "<tabela>", "syncMode": "full_refresh_overwrite"}`
   para cada tabela.
5. `POST /jobs` com `{"connectionId": "...", "jobType": "sync"}` e acompanhar
   `GET /jobs/<jobId>` até `succeeded`.

## Local x EKS
| | Local (kind) | EKS |
|---|---|---|
| Endpoint S3 do destination | `http://minio-local-hl.data-platform.svc.cluster.local:9000` | `http://minio-eks-hl.data-platform.svc.cluster.local:9000` |
| UI | `http://localhost:8001` (porta mapeada no kind) | LoadBalancer, porta 8001 |

O resto (source, formato, path, modos) é idêntico. As chaves S3 são de
cada ambiente, sempre lidas do `airbyte-storage-secret` do cluster em uso.

## Opcional: dataset completo (MovieLens)
O seed do repo não traz o `ml-latest-small` (~100 mil ratings). Para carregá-lo
no sample sem alterar o schema (idempotente, mantém o que já existe):
```bash
curl -sLO https://files.grouplens.org/datasets/movielens/ml-latest-small.zip && unzip -qo ml-latest-small.zip
POD=$(kubectl get pod -n ingestion -l app=sample-source-postgres -o jsonpath='{.items[0].metadata.name}')
for t in movies links ratings tags; do kubectl cp ml-latest-small/$t.csv ingestion/$POD:/tmp/$t.csv; done
kubectl exec -i -n ingestion $POD -- psql -U sample -d movielens -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;
CREATE TEMP TABLE s_movies  (movieid int, title text, genres text) ON COMMIT DROP;
CREATE TEMP TABLE s_links   (movieid int, imdbid int, tmdbid int) ON COMMIT DROP;
CREATE TEMP TABLE s_ratings (userid int, movieid int, rating numeric(2,1), ts bigint) ON COMMIT DROP;
CREATE TEMP TABLE s_tags    (userid int, movieid int, tag text, ts bigint) ON COMMIT DROP;
\copy s_movies  FROM '/tmp/movies.csv'  WITH (FORMAT csv, HEADER true)
\copy s_links   FROM '/tmp/links.csv'   WITH (FORMAT csv, HEADER true)
\copy s_ratings FROM '/tmp/ratings.csv' WITH (FORMAT csv, HEADER true)
\copy s_tags    FROM '/tmp/tags.csv'    WITH (FORMAT csv, HEADER true)
INSERT INTO movies  SELECT * FROM s_movies  ON CONFLICT (movieid) DO NOTHING;
INSERT INTO links   SELECT * FROM s_links   ON CONFLICT (movieid) DO NOTHING;
INSERT INTO ratings (userid,movieid,rating,"timestamp") SELECT * FROM s_ratings ON CONFLICT DO NOTHING;
INSERT INTO tags (userid,movieid,tag,"timestamp") SELECT s.* FROM s_tags s
  WHERE NOT EXISTS (SELECT 1 FROM tags t WHERE t.userid=s.userid AND t.movieid=s.movieid AND t.tag=s.tag AND t."timestamp"=s.ts);
COMMIT;
SQL
```
Atenção: use `kubectl cp` + `\copy` de arquivo. Mandar os CSVs por `stdin` do
`kubectl exec -i` falha com arquivos grandes. Essa carga fica **só no
Postgres em execução**: se o cluster for recriado, o sample volta às 200
linhas do seed. O seed original (de uma versão antiga do MovieLens) tem 3
filmes e alguns ratings/tags que não existem no dataset atual; eles
permanecem depois da carga.
