# SPEC-012: Metabase — Plano de Implementação

**Status:** Aguardando aprovação

---

## 1. Resumo

Metabase conectado ao Trino para visualização dos dados Iceberg.

## 2. Tarefas

### Tarefa 1: PostgreSQL dedicado
Backend do Metabase (metadados, usuários, dashboards salvos).

### Tarefa 2: Deployment Metabase
- Imagem: `metabase/metabase:latest`
- Variáveis de ambiente para conexão com Postgres

### Tarefa 3: ArgoCD Application

### Tarefa 4: Configurar conexão Trino (via UI)
- Database type: Starburst (Trino)
- Host: `trino.query-engine.svc.cluster.local`
- Port: `8080`
- Catalog: `iceberg`

## 3. Recursos

| Componente | CPU | Memory |
|------------|-----|--------|
| Metabase | 500m | 1Gi |
| PostgreSQL | 100m | 256Mi |

## 4. Validação

```bash
# Metabase UI
kubectl port-forward svc/metabase -n data-platform 3000:3000
# http://localhost:3000
```

---

**Aprovado?**
