# OpenMetadata Connectors Setup

## Acesso à UI

```bash
kubectl port-forward svc/openmetadata -n governance 8585:8585
```

Acessar: http://localhost:8585

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

1. Settings → Services → Pipelines → Add New Service
2. Selecionar **Airflow**
3. Configurar:
   - **Host**: `http://airflow-webserver.orchestration.svc.cluster.local:8080`
   - **Connection**: `airflow_default`
4. Test Connection → Save

## Connector: dbt

1. Settings → Services → Pipelines → Add dbt
2. Configurar:
   - **Source**: Local Config
   - **dbt Catalog File**: upload `target/catalog.json`
   - **dbt Manifest File**: upload `target/manifest.json`
3. Save

## Rodar Ingestion

Para cada connector:
1. Ir em Ingestion → Add Ingestion
2. Configurar schedule (ou rodar manualmente)
3. Run Now

## Verificar Linhagem

Após ingestion:
1. Ir em Explore → Tables
2. Selecionar uma tabela gold (ex: `gold_top_movies`)
3. Verificar tab "Lineage" com o fluxo completo
