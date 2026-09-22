# OpenMetadata Connectors Setup

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
   - **Host**: `trino.query-engine.svc.cluster.local`
   - **Port**: `8080`
   - **Username**: `admin`
   - **Catalog**: `iceberg`
   - **Database Schema**: `default`
4. Test Connection → Save

## Connector: Airflow

Este connector faz *harvesting* (leitura) de metadata do Airflow
**principal** da plataforma (não o Managed Airflow acima) — DAGs e
execuções da pipeline de dados (ex: `dbt_movielens`).

1. Settings → Services → Pipelines → Add New Service
2. Selecionar **Airflow**
3. Configurar:
   - **Host**: `http://airflow-api-server.ingestion.svc.cluster.local:8080`
   - **Connection**: `airflow_default`
4. Test Connection → Save

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

## Verificar Linhagem

Após ingestion:
1. Ir em Explore → Tables
2. Selecionar uma tabela gold (ex: `gold_movie_recommendations`)
3. Verificar tab "Lineage" com o fluxo completo
