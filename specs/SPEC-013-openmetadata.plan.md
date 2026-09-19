# SPEC-014: OpenMetadata — Plano de Implementação

**Status:** Aguardando aprovação

---

## 1. Resumo

Catálogo de dados com linhagem. Conectores para Trino, Airflow e dbt.

## 2. Componentes

| Componente | Função |
|------------|--------|
| OpenMetadata | Catálogo e linhagem |
| OpenSearch | Busca e indexação |
| PostgreSQL | Backend do OpenMetadata |

## 3. Tarefas

### Tarefa 1: PostgreSQL dedicado
```yaml
# charts/openmetadata/postgres.yaml
StatefulSet para openmetadata-postgres
```

### Tarefa 2: OpenSearch
Usar chart oficial `opensearch` com configuração mínima (1 node, recursos limitados).

### Tarefa 3: OpenMetadata Helm Chart
```yaml
# charts/openmetadata/values-local.yaml
openmetadata:
  config:
    database:
      host: openmetadata-postgres
    elasticsearch:
      host: opensearch
```

### Tarefa 4: ArgoCD Applications
- `opensearch-app.yaml`
- `openmetadata-app.yaml`

### Tarefa 5: Configurar Connectors (via UI)
1. Trino connector → schemas Iceberg
2. Airflow connector → DAGs e execuções
3. dbt connector → models e linhagem

## 4. Recursos (ambiente local)

| Componente | CPU | Memory |
|------------|-----|--------|
| OpenMetadata | 500m | 1Gi |
| OpenSearch | 500m | 1Gi |
| PostgreSQL | 100m | 256Mi |

**Total extra:** ~1.1 CPU, ~2.5Gi RAM

## 5. Simplificações

- OpenSearch single-node
- Sem autenticação no OpenMetadata (dev mode)
- Connectors configurados via UI (não automatizado)

## 6. Validação

```bash
# Pods running
kubectl get pods -n governance

# OpenMetadata UI
kubectl port-forward svc/openmetadata -n governance 8585:8585
```

---

**Aprovado?**
