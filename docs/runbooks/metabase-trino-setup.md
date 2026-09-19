# Metabase + Trino Setup

## Acesso ao Metabase

```bash
kubectl port-forward svc/metabase -n data-platform 3000:3000
```

Acessar: http://localhost:3000

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

## Testar Conexão

1. New → Question → Native query
2. Selecionar "Lakehouse Trino"
3. Executar:
   ```sql
   SELECT * FROM gold.gold_top_movies LIMIT 10
   ```

## Criar Dashboard

1. New → Dashboard
2. Adicionar cards com queries nas tabelas gold:
   - `gold_top_movies` - Top filmes
   - `gold_genre_popularity` - Popularidade por gênero
   - `gold_rating_trends` - Tendências de avaliações
