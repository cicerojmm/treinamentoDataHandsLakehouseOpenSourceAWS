# SPEC-009: DAG Principal (Bronze Tables → dbt build)

**Fase do projeto:** 2 — Camada de Código
**Pré-requisitos:** SPEC-005 (Airflow), SPEC-007 (Trino), SPEC-008 (dbt)
**Bloqueia:** SPEC-010 (API, depende de dados curados existirem de forma recorrente)
**Status:** Implementado

---

## 1. Contexto
DAG principal do lakehouse que:
1. Cria external tables no catálogo `hive_bronze` apontando para arquivos Parquet no bucket bronze (dados raw do Airbyte)
2. Executa dbt que lê da bronze via Trino e escreve tabelas Iceberg no bucket warehouse (staging/silver/gold)

Fluxo de dados:
```
s3://bronze (Parquet) → hive_bronze (Trino) → dbt → s3://warehouse (Iceberg)
                                                      ├── staging/ (views)
                                                      ├── silver/  (tabelas)
                                                      └── gold/    (tabelas)
```

## 2. Arquivos criados
```
code/airflow-dags/dags/
└── dbt_movielens_dag.py
```
(adicionado ao mesmo repositório de imagem do SPEC-005 — nova imagem,
novo SHA, novo deploy via ArgoCD)

## 3. Especificação técnica

### 3.1 Estrutura da DAG
```
create_bronze_schema
         ↓
[create_movies_table, create_ratings_table, create_links_table, create_tags_table]  (paralelo)
         ↓
dbt_transform (TaskGroup com todos os models dbt)
```

### 3.2 Operadores utilizados
- `SQLExecuteQueryOperator` (Airflow 3.x): executa DDL no Trino via conexão `trino_default`
- `DbtTaskGroup` (astronomer-cosmos): executa models dbt como tasks individuais

### 3.3 External Tables Bronze
Tabelas criadas com `CREATE TABLE IF NOT EXISTS` apontando para:
- `s3://bronze/movielens/movies/`
- `s3://bronze/movielens/ratings/`
- `s3://bronze/movielens/links/`
- `s3://bronze/movielens/tags/`

### 3.4 Configuração
- Conexão Trino: `trino_default` (host: trino.data-platform.svc.cluster.local:8080)
- Agendamento: manual (trigger on-demand)
- Retry policy: 1 retry com backoff

## 4. Ordem de execução
```
1. Build + push da nova imagem do Airflow com a DAG
2. Atualizar tag no values-local.yaml, Helm upgrade
3. Configurar a connection trino_default na UI do Airflow
4. Disparar a DAG manualmente para validar
```

## 5. Critério de Aceite
1. [x] DAG aparece na UI do Airflow e pode ser disparada manualmente
2. [x] Tasks de criação de schema e tabelas completam com sucesso
3. [x] dbt_transform executa todos os models (staging → silver → gold)
4. [x] Dados aparecem no bucket warehouse como tabelas Iceberg
5. [x] API consegue ler os dados do gold via DuckDB

## 6. Rollback / Recuperação
Reverter para a imagem anterior do Airflow (SHA anterior) remove a DAG
problemática sem afetar as demais.

## 7. Fora de escopo
- Trigger automático do Airbyte — sync manual por enquanto
- Great Expectations como task intermediária — SPEC futura
- Alertas via Slack/email — placeholder para melhoria futura

## 8. Notas de implementação
- Airflow 3.x deprecou `TrinoOperator`, substituído por `SQLExecuteQueryOperator`
- Cada statement DDL é uma task separada para melhor visibilidade e retry granular
- dbt usa `astronomer-cosmos` com `TrinoLDAPProfileMapping` para gerar tasks automaticamente
