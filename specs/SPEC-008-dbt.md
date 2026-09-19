# SPEC-008: Projeto dbt (Movielens - Silver/Gold)

**Fase do projeto:** 2 — Camada de Código
**Pré-requisitos:** SPEC-002 (ECR), SPEC-006 (Airbyte), SPEC-007 (Trino)
**Bloqueia:** SPEC-009 (DAG principal), SPEC-010 (API), SPEC-014 (OpenMetadata)
**Status:** Implement

---

## 1. Contexto
Camada de transformação SQL sobre o Trino usando dbt-trino. Projeto baseado
no dataset Movielens (links, movies, ratings, tags) extraído pelo Airbyte do
Postgres de exemplo para o bronze layer no MinIO.

Orquestração via Astronomer Cosmos integrado ao Airflow 3.3.0.

## 2. Arquivos a criar
```
code/dbt-project/
├── Dockerfile
├── dbt_project.yml
├── profiles/
│   └── profiles.yml
├── models/
│   ├── sources.yml           # fontes bronze (Airbyte)
│   ├── silver/
│   │   ├── silver_movies.sql
│   │   ├── silver_ratings.sql
│   │   ├── silver_links.sql
│   │   └── silver_tags.sql
│   └── gold/
│       ├── gold_movie_analytics.sql
│       ├── gold_user_behavior.sql
│       ├── gold_genre_analytics.sql
│       ├── gold_temporal_trends.sql
│       └── gold_movie_recommendations.sql
├── tests/
└── packages.yml
```

## 3. Especificação técnica

### 3.1 Dockerfile
```dockerfile
FROM python:3.11-slim

RUN pip install --no-cache-dir \
    dbt-core==1.9.* \
    dbt-trino==1.9.*

WORKDIR /dbt
COPY . .
RUN mkdir -p /root/.dbt
COPY profiles/profiles.yml /root/.dbt/profiles.yml

ENV DBT_PROFILES_DIR=/root/.dbt

ENTRYPOINT ["dbt"]
CMD ["--help"]
```

### 3.2 profiles.yml
```yaml
movielens:
  target: local
  outputs:
    local:
      type: trino
      host: "{{ env_var('DBT_TRINO_HOST', 'trino.query-engine.svc.cluster.local') }}"
      port: 8080
      user: admin
      catalog: iceberg
      schema: silver
      threads: 4
```

### 3.3 Camadas de dados

**Bronze (sources):** Dados raw extraídos pelo Airbyte do Postgres movielens
- `iceberg.bronze.links` - IDs IMDB/TMDB
- `iceberg.bronze.movies` - Títulos e gêneros
- `iceberg.bronze.ratings` - Avaliações de usuários
- `iceberg.bronze.tags` - Tags de usuários

**Silver:** Dados limpos e tipados
- `iceberg.silver.silver_movies` - Filmes com ano extraído, flags de gênero
- `iceberg.silver.silver_ratings` - Ratings com datetime, categorias
- `iceberg.silver.silver_links` - Links externos normalizados
- `iceberg.silver.silver_tags` - Tags normalizadas com análise de sentimento

**Gold:** Agregações analíticas
- `iceberg.gold.gold_movie_analytics` - Métricas por filme
- `iceberg.gold.gold_user_behavior` - Padrões de comportamento de usuários
- `iceberg.gold.gold_genre_analytics` - Análise por gênero
- `iceberg.gold.gold_temporal_trends` - Tendências temporais
- `iceberg.gold.gold_movie_recommendations` - Base para recomendações

### 3.4 Cosmos (Airflow)
Instalar `astronomer-cosmos` no Airflow e criar DAG que:
1. Renderiza o projeto dbt como TaskGroups
2. Executa via `DbtTaskGroup` ou `DbtDag`
3. Conecta ao Trino usando ProfileConfig

## 4. Ordem de execução esperada
```
1. Criar tabelas bronze no Iceberg (via Airbyte ou manualmente para teste)
2. Build da imagem dbt (docker build)
3. Push para ECR
4. dbt debug (valida conexão Trino)
5. dbt run --select silver (cria camada silver)
6. dbt run --select gold (cria camada gold)
7. dbt test
```

## 5. Critério de Aceite
1. `docker build` da imagem dbt completa sem erro
2. `dbt debug` confirma conexão bem-sucedida com o Trino
3. `dbt run` executa com sucesso, criando tabelas silver e gold no catálogo iceberg
4. `dbt test` passa (not_null, unique, relationships)
5. Tabelas gold visíveis no bucket gold do MinIO
6. Cosmos consegue renderizar e executar o projeto no Airflow

## 6. Rollback / Recuperação
`dbt run --full-refresh` recria os modelos do zero.

## 7. Fora de escopo
- CI/CD automatizado (SPEC-011)
- Particionamento avançado de tabelas Iceberg

## 8. Dataset Movielens
Fonte: https://grouplens.org/datasets/movielens/
- **links.csv**: movieId, imdbId, tmdbId
- **movies.csv**: movieId, title, genres
- **ratings.csv**: userId, movieId, rating, timestamp
- **tags.csv**: userId, movieId, tag, timestamp

Dados de exemplo serão carregados no Postgres source e extraídos pelo Airbyte.
