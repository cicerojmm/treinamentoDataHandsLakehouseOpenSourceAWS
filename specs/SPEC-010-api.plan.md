# SPEC-010: API FastAPI + DuckDB — Plano de Implementação

**Status:** Aguardando aprovação

---

## 1. Resumo

API de exemplo com DuckDB consumindo Parquet direto do MinIO (camada gold).

## 2. Endpoints (simplificado)

| Endpoint | Descrição |
|----------|-----------|
| `GET /health` | Health check (sem auth) |
| `GET /movies` | Lista top filmes com stats |
| `GET /movies/{id}` | Detalhes de um filme |
| `GET /genres` | Popularidade por gênero |
| `GET /stats` | Estatísticas gerais |

## 3. Arquitetura

```
Request → FastAPI → X-API-Key check → DuckDB → Iceberg tables (MinIO) → Response
```

- DuckDB com extensões `iceberg` + `httpfs`
- Lê tabelas Iceberg criadas pelo Trino/dbt no MinIO
- Path: `s3://gold/warehouse/<schema>/<table>/`
- Stateless, sem persistência local

```python
# Exemplo de query
duckdb.sql("""
    SELECT * FROM iceberg_scan('s3://gold/warehouse/gold/gold_top_movies/')
""")

## 4. Tarefas

### Tarefa 1: Estrutura do projeto
```
code/api-service/
├── Dockerfile
├── requirements.txt
├── app/
│   ├── main.py
│   ├── config.py
│   ├── auth.py
│   └── routers/
│       └── movies.py
```

### Tarefa 2: Código da API
- FastAPI com 4 endpoints
- DuckDB client conectando ao MinIO
- Middleware de API key simples

### Tarefa 3: Dockerfile
```dockerfile
FROM python:3.11-slim
RUN pip install fastapi uvicorn duckdb
COPY app/ /app/
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Tarefa 4: Manifests Kubernetes
- Deployment (1 réplica para exemplo)
- Service (ClusterIP)
- Secret (API key)

### Tarefa 5: ArgoCD Application

### Tarefa 6: Build/push e deploy

## 5. Simplificações (API de exemplo)

- Sem HPA (1 réplica fixa)
- Sem testes automatizados
- API key hardcoded no Secret (não rotacionável)
- Sem paginação nos endpoints

## 6. Validação

```bash
# Health check
curl http://<api>/health

# Com API key
curl -H "X-API-Key: <key>" http://<api>/movies
curl -H "X-API-Key: <key>" http://<api>/genres
```

---

**Aprovado?**
