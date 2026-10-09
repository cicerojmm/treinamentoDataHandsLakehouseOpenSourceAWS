# Runbook: OpenMetadata Connectors

## Acesso à UI

No EKS, via LoadBalancer (ver `make urls-eks`). Local/port-forward:

```bash
kubectl --context=data-platform-eks port-forward svc/openmetadata -n governance 8585:8585
```

Acessar: http://localhost:8585

## Managed Airflow (pré-requisito para rodar qualquer ingestion)

Desde o SPEC-013 (seção 3.3), o OpenMetadata usa um Airflow **próprio**,
dedicado (`openmetadata-dependencies`, chart
`open-metadata/openmetadata-dependencies`), diferente do Airflow
principal da plataforma. É esse Airflow que executa o botão
"Deploy"/"Run Now" de qualquer Ingestion Pipeline na UI.

Verificar que está saudável antes de configurar os connectors:
```bash
kubectl --context=data-platform-eks get pods -n governance | grep openmetadata-dependencies
```
Settings → Pipeline Services na UI não deve mostrar erro de conexão
(`ConnectException` em `openmetadata-dependencies-web`).

## Connector: Trino

1. Settings → Services → Databases → Add New Service
2. Selecionar **Trino**
3. Configurar:
   - **Host and Port**: `trino.query-engine.svc.cluster.local:8080`
     — **sem** `http://`. O campo vira `hostPort` e o conector quebra o
     valor em `:`; com o esquema na frente a ingestion falha em menos de 1 s
     com `ValueError: invalid literal for int() with base 10: ''`
     (e o Test Connection pode até passar).
   - **Username**: `admin`
   - **Catalog**: `iceberg`
   - **Database Schema**: `default`
4. Test Connection → Save

## Connector: MinIO (Storage / S3)

Cataloga os arquivos brutos do lakehouse (Parquet do Airbyte em
`bronze/movielens/*`). As tabelas Iceberg do `warehouse` vêm pelo
connector Trino acima.

1. Settings → Services → Storages → Add New Service
2. Selecionar **S3**, nome `MinIO Lakehouse`
3. Configurar:
   - **AWS Access Key / Secret**: as chaves do MinIO (rotacionadas — não são
     mais `minio`/`minio123`). Leia do cluster, sem colar em lugar nenhum:
     ```bash
     kubectl get secret airbyte-storage-secret -n ingestion -o jsonpath='{.data.s3-access-key-id}' | base64 -d; echo
     kubectl get secret airbyte-storage-secret -n ingestion -o jsonpath='{.data.s3-secret-access-key}' | base64 -d; echo
     ```
   - **AWS Region**: `us-east-2` (qualquer valor serve pro MinIO)
   - **Endpoint URL**: `http://minio-eks-hl.data-platform.svc.cluster.local:9000`
4. Test Connection → Save. O aviso de `GetMetrics` é esperado, porque o
   MinIO não tem CloudWatch.
5. Na ingestion de metadata, **Container Filter Pattern**: deixar
   vazio ou usar `.*`. **Não usar `*`**: o campo é regex, e `*` é
   inválido. A listagem falha ("Invalid regex [*]") e o
   `markDeletedContainers` marca todos os buckets como deletados, mas
   a execução mesmo assim aparece como `success`.

Os schemas dos Parquet dependem do manifest `bronze/openmetadata.json`,
gravado pelo Job `minio-create-buckets` (`charts/minio-eks-setup/`).
Novo dataset em `bronze` = nova entrada no manifest desse Job.

Esperado após rodar: containers `bronze.movielens/{movies,ratings,links,tags}`
com colunas.

## Connector: Airflow

Este connector faz *harvesting* (leitura) de metadata do Airflow
**principal** da plataforma (não o Managed Airflow acima) — DAGs e
execuções da pipeline de dados (ex: `dbt_movielens`).

1. Settings → Services → Pipelines → Add New Service
2. Selecionar **Airflow**
3. Configurar:
   - **Host**: `http://airflow-api-server.ingestion.svc.cluster.local:8080`
     (aqui o esquema `http://` é necessário, ao contrário do Trino; no
     ambiente local o namespace é `orchestration`)
   - **Connection**: `airflow_default`
4. Test Connection → Save

> O Airflow 3 do projeto usa o auth manager FAB, com a API v2 protegida por
> token JWT. Este passo de credenciais do connector não foi revalidado
> contra essa configuração; se o Test Connection falhar com 401/403, é o
> primeiro ponto a conferir.

## Connector: dbt

1. Settings → Services → Pipelines → Add dbt
2. Configurar:
   - **Source**: Local Config
   - **dbt Catalog File**: upload `target/catalog.json`
   - **dbt Manifest File**: upload `target/manifest.json`
3. Save

> Esses arquivos não são persistidos hoje em nenhum lugar acessível —
> o `dbt build`/`dbt test` roda dentro de pods de task do Airflow que
> são apagados logo após terminar (`delete_worker_pods: true`). É
> preciso gerar/extrair `manifest.json`/`catalog.json` manualmente
> (ex: rodando `dbt build --project-dir code/dbt-project` localmente
> ou num pod temporário) antes deste passo.

## Rodar Ingestion

Para cada connector:
1. Ir em Ingestion → Add Ingestion
2. Configurar schedule (ou rodar manualmente)
3. Deploy / Run Now

Isso dispara uma execução no Managed Airflow (acima) — se ele não
estiver saudável, o Deploy/Run Now falha.

## Troubleshooting

**Ingestion falhou: onde ver o erro.** A UI mostra só "failed". O log
completo está no Airflow do próprio OpenMetadata (a task roda no scheduler):
```bash
kubectl exec -n governance deploy/openmetadata-dependencies-scheduler -c airflow-scheduler -- sh -c \
  'f=$(find /opt/airflow/logs -name "attempt=*.log" | xargs ls -t | head -1); grep -iE "error|exception|Traceback|Summary|Success" "$f" | tail -20'
```
Um resumo `Errors: 0` e `Success %: 100.0` indica ingestion saudável.

**Recriar um service com o mesmo nome.** Excluir um service na UI faz
*soft delete*: o service e as suas pipelines continuam no banco (com
`deleted=true`) e seguram o nome. Para recriar com o mesmo nome, faça
*hard delete* (permanent delete) do service e da pipeline órfã, ou use
outro nome. Conferir o que sobrou:
```bash
# precisa de um token JWT do OpenMetadata
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://<openmetadata>:8585/api/v1/services/ingestionPipelines?include=deleted"
```
A pipeline excluída deixa de existir no Airflow do OM, mas pode continuar
aparecendo na UI até o hard delete (registro no banco e no índice de busca).

**Corrigir só a conexão de um service existente** (ex.: `hostPort` errado)
não exige recriar: edite o service na UI (ou `PATCH` em
`/api/v1/services/databaseServices/<id>`) e rode a ingestion de novo.

**Perda de configuração.** Services, pipelines e schedules vivem no Postgres
do OpenMetadata; se o cluster for recriado, este runbook inteiro precisa
ser refeito.

## Verificar Linhagem

Após ingestion:
1. Ir em Explore → Tables
2. Selecionar uma tabela gold (ex: `gold_movie_recommendations`)
3. Verificar tab "Lineage" com o fluxo completo
