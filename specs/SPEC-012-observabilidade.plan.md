# SPEC-013: Observabilidade — Plano de Implementação

**Status:** Aguardando aprovação

---

## 1. Resumo

Instalar kube-prometheus-stack (Prometheus + Grafana) com dashboards para Airflow, Trino e MinIO.

## 2. Componentes

| Componente | Função |
|------------|--------|
| Prometheus | Coleta métricas |
| Grafana | Visualização |
| Alertmanager | Alertas (instalado, sem regras) |

## 3. Tarefas

### Tarefa 1: Criar namespace e estrutura
```bash
kubectl create namespace observability
```

### Tarefa 2: values-local.yaml
```yaml
# charts/observability/values-local.yaml
prometheus:
  prometheusSpec:
    retention: 15d
    serviceMonitorSelectorNilUsesHelmValues: false
grafana:
  adminPassword: admin123
  service:
    type: ClusterIP
```

### Tarefa 3: ArgoCD Application
```yaml
# apps/local/kube-prometheus-stack-app.yaml
spec:
  source:
    chart: kube-prometheus-stack
    repoURL: https://prometheus-community.github.io/helm-charts
```

### Tarefa 4: ServiceMonitors
- MinIO: endpoint `/minio/v2/metrics/cluster`
- Trino: JMX exporter (se habilitado)
- Airflow: StatsD ou métricas nativas

### Tarefa 5: Dashboards (opcional)
- Usar dashboards da comunidade (IDs do Grafana.com)
- Ou criar ConfigMaps com JSON customizado

## 4. Simplificações

- Dashboards da comunidade em vez de customizados
- Sem regras de alertas
- Retenção padrão 15 dias

## 5. Validação

```bash
# Pods running
kubectl get pods -n observability

# Grafana UI
kubectl port-forward svc/kube-prometheus-stack-grafana -n observability 3000:80

# Prometheus targets
kubectl port-forward svc/kube-prometheus-stack-prometheus -n observability 9090:9090
```

---

**Aprovado?**
