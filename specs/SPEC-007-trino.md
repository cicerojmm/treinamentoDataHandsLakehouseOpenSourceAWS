# SPEC-007: Trino com Catálogo Iceberg

**Fase do projeto:** 1 — Core de Infraestrutura
**Pré-requisitos:** SPEC-004 (Hive Metastore PostgreSQL)
**Bloqueia:** SPEC-008 (dbt), SPEC-010 (API), SPEC-014 (OpenMetadata, ingestion do catálogo)
**Status:** Implemented

---

## 1. Contexto
Motor de consulta SQL federado, usado pelo dbt (transformação) e pela
API (serving). Este spec configura o catálogo Iceberg do Trino usando o
JDBC catalog com PostgreSQL dedicado para metadados.

**Nota:** A configuração usa JDBC catalog em vez de Hive Metastore para
evitar incompatibilidade entre o filesystem S3A do Hadoop (usado pelo Hive)
e o filesystem nativo S3 do Trino 480+. O JDBC catalog armazena metadados
Iceberg em tabelas PostgreSQL dedicadas e usa o filesystem nativo do Trino
para acesso ao MinIO.

## 2. Arquivos a criar
```
charts/trino/
├── values-local.yaml
└── catalogs/
    └── iceberg.properties        # configuração do catálogo
apps/local/trino-app.yaml
```

## 3. Especificação técnica

### 3.1 Catálogo Iceberg (JDBC Catalog)
```properties
connector.name=iceberg
iceberg.catalog.type=jdbc
iceberg.jdbc-catalog.driver-class=org.postgresql.Driver
iceberg.jdbc-catalog.connection-url=jdbc:postgresql://hive-metastore-postgres.data-platform.svc.cluster.local:5432/iceberg_catalog
iceberg.jdbc-catalog.connection-user=hive
iceberg.jdbc-catalog.connection-password=hive123
iceberg.jdbc-catalog.catalog-name=iceberg
iceberg.jdbc-catalog.default-warehouse-dir=s3://gold/warehouse
fs.native-s3.enabled=true
s3.endpoint=http://minio-local-hl.data-platform.svc.cluster.local:9000
s3.path-style-access=true
s3.region=us-east-1
s3.aws-access-key=minio
s3.aws-secret-key=minio123
```

Nota: Para Trino 463+, usar `fs.native-s3.enabled=true` e `s3.*` para
acesso ao MinIO. A propriedade `s3.region` é obrigatória.

### 3.2 JDBC Catalog Schema
O JDBC catalog requer as seguintes tabelas no PostgreSQL (criadas automaticamente
ou manualmente no banco `iceberg_catalog`):

```sql
CREATE TABLE IF NOT EXISTS iceberg_tables (
    catalog_name VARCHAR(255) NOT NULL,
    table_namespace VARCHAR(255) NOT NULL,
    table_name VARCHAR(255) NOT NULL,
    metadata_location VARCHAR(1000),
    previous_metadata_location VARCHAR(1000),
    PRIMARY KEY (catalog_name, table_namespace, table_name)
);

CREATE TABLE IF NOT EXISTS iceberg_namespace_properties (
    catalog_name VARCHAR(255) NOT NULL,
    namespace VARCHAR(255) NOT NULL,
    property_key VARCHAR(255) NOT NULL,
    property_value VARCHAR(1000),
    PRIMARY KEY (catalog_name, namespace, property_key)
);
```

### 3.3 Dimensionamento local
Single node (workers=0) com `coordinator.config.nodeScheduler.includeCoordinator=true`
para permitir execução de queries no coordinator. Recursos compatíveis com cluster
kind de 16GB RAM.

### 3.4 Versão
Trino 480 com Iceberg 1.10.1 embutido.

## 4. Ordem de execução esperada
```
1. Criar banco de dados iceberg_catalog no PostgreSQL
2. Criar tabelas de metadados do JDBC catalog (se não auto-criadas)
3. ArgoCD sincroniza trino-app (coordinator single-node)
4. Validar conectividade com MinIO
5. Criar schema de teste no catálogo iceberg via trino-cli
```

## 5. Critério de Aceite
1. `kubectl get pods -n query-engine` mostra coordinator em `Running`
2. Via `trino-cli` (ou UI web do Trino): `SHOW CATALOGS` lista `iceberg`
3. `CREATE SCHEMA iceberg.staging` executa sem erro
4. `CREATE TABLE iceberg.staging.teste (id int) WITH (format = 'PARQUET')`
   seguido de `INSERT` e `SELECT` funciona ponta a ponta
5. A tabela criada é visível como arquivo físico no bucket `gold` do
   MinIO (`mc ls minio/gold/warehouse/staging/teste/`)

## 6. Rollback / Recuperação
Schemas/tabelas de teste podem ser dropadas livremente
(`DROP SCHEMA ... CASCADE`) sem afetar a infraestrutura.

## 7. Fora de escopo
- Catálogos adicionais além do Iceberg (ex: catálogo Postgres para
  consultas federadas a bancos de metadados) — avaliar se necessário
  mais adiante
- Tuning de performance de queries — só relevante com volume de dados real
- Hive Metastore como catálogo Iceberg — incompatibilidade de filesystem
  com Trino 480+ (usar JDBC catalog em vez disso)

## 8. Decisões técnicas

### 8.1 Por que JDBC Catalog em vez de Hive Metastore?
O Trino 480+ usa um cliente S3 nativo (`fs.native-s3.enabled=true`) que
trabalha com o scheme `s3://`. O Hive Metastore usa Hadoop S3A que trabalha
com `s3a://`. Quando o Trino tenta criar tabelas via Hive Metastore, ocorre
incompatibilidade de filesystem.

O JDBC catalog:
- Armazena metadados em tabelas PostgreSQL simples
- Não depende do Hive para operações de filesystem
- Permite uso do filesystem nativo S3 do Trino
- Menor footprint que manter Hive Metastore rodando

### 8.2 Configurações críticas para Single-Node
```yaml
coordinator.config.nodeScheduler.includeCoordinator: true
server.workers: 0
```
Sem `includeCoordinator=true`, queries ficam em QUEUED aguardando workers
que não existem.
