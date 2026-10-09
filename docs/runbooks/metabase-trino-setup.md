# Runbook: Metabase + Trino

## Acesso ao Metabase

No EKS, via LoadBalancer na porta 3000 (`make urls-eks`). Em qualquer
ambiente, por port-forward (no EKS, acrescente `--context=data-platform-eks`):

```bash
kubectl port-forward svc/metabase -n data-platform 3000:3000
```

Acessar: http://localhost:3000

O Metabase guarda a configuração no Postgres dedicado (`metabase-postgres`).
Se o cluster for recriado, a conta admin e a conexão com o Trino precisam
ser refeitas.

## Setup Inicial

1. Criar conta admin (primeiro acesso)
2. Pular configuração de banco (fazer depois)

## Configurar Conexão Trino

1. Settings (engrenagem) → Admin settings → Databases → Add database

2. Configurar:
   - **Database type**: Starburst (Trino)
   - **Display name**: Lakehouse Trino
   - **Host**: `trino.query-engine.svc.cluster.local`
   - **Port**: `8080`
   - **Catalog**: `iceberg`
   - **Schema** (opcional): `gold`
   - **Username**: `admin`
   - **Password**: (deixar vazio)

3. Clicar "Save"

O Trino não tem autenticação nesta plataforma, por isso o usuário é só um
nome e a senha fica vazia.

## Testar Conexão

1. New → Question → Native query
2. Selecionar "Lakehouse Trino"
3. Executar:
   ```sql
   SELECT * FROM gold.gold_movie_analytics LIMIT 10
   ```
   Se der "table does not exist", a DAG `dbt_movielens` ainda não rodou
   (as tabelas gold são criadas por ela). Conferir as tabelas existentes:
   ```bash
   kubectl exec -n query-engine deploy/trino-coordinator -- trino --execute "SHOW TABLES FROM iceberg.gold"
   ```

## Criar Dashboard

1. New → Dashboard
2. Adicionar cards com queries nas tabelas gold:
   - `gold_movie_analytics` - Métricas por filme (notas, popularidade)
   - `gold_genre_analytics` - Análise por gênero
   - `gold_temporal_trends` - Tendências de avaliações ao longo do tempo
   - `gold_user_behavior` - Comportamento dos usuários
   - `gold_movie_recommendations` - Recomendações
   - `gold_external_links` - Links externos (IMDB/TMDB)
