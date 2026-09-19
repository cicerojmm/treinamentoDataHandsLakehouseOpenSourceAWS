# SPEC-013: kube-prometheus-stack + Dashboards Grafana

**Fase do projeto:** 3 — Observabilidade e Governança
**Pré-requisitos:** SPEC-001
**Bloqueia:** nenhum spec técnico direto — observabilidade é transversal
**Status:** Specify

---

## 1. Contexto
Métricas de cluster e dashboards operacionais dos componentes já
implantados (Airflow, Trino, MinIO). Usa o chart `kube-prometheus-stack`,
que já empacota Prometheus + Grafana juntos.

## 2. Arquivos a criar
```
charts/observability/
└── values-local.yaml
apps/local/kube-prometheus-stack-app.yaml
docs/dashboards/
├── airflow-dag-runs.json
├── trino-query-performance.json
└── minio-storage-usage.json
```

## 3. Especificação técnica

### 3.1 Scraping
Habilitar `ServiceMonitor`/`PodMonitor` para: Airflow (métricas via
StatsD exporter ou endpoint nativo, conforme versão), Trino (endpoint
JMX/Prometheus), MinIO (endpoint `/minio/v2/metrics/cluster`).

### 3.2 Dashboards
Três dashboards mínimos, importados como ConfigMap (padrão do chart
para auto-provisionamento no Grafana):
- DAG runs (sucesso/falha, duração) — Airflow
- Query performance (tempo de execução, queries ativas) — Trino
- Storage usage (uso de disco por bucket) — MinIO

## 4. Ordem de execução esperada
```
1. ArgoCD sincroniza kube-prometheus-stack-app
2. Validar targets do Prometheus (todos "UP")
3. Importar/validar os 3 dashboards no Grafana
```

## 5. Critério de Aceite
1. `kubectl get pods -n observability` mostra Prometheus, Grafana e
   Alertmanager em `Running`
2. UI do Prometheus (`/targets`) mostra Airflow, Trino e MinIO como `UP`
3. Grafana acessível via port-forward, com os 3 dashboards populados com
   dados reais (não vazios)
4. Disparar uma DAG no Airflow e ver o resultado refletido no dashboard
   correspondente em até 1 minuto (intervalo de scrape padrão)

## 6. Rollback / Recuperação
Componente stateless em relação ao resto da plataforma — reinstalar não
afeta dados de negócio, só histórico de métricas.

## 7. Fora de escopo
- Alertas configurados (Alertmanager fica instalado mas sem regras
  customizadas nesta fase) — considerar spec futuro se necessário
- Retenção de longo prazo de métricas (avaliar storage externo se o
  volume crescer)

## 8. Decisões assumidas
- Retenção padrão do Prometheus local: 15 dias (valor default do chart)
  — suficiente para desenvolvimento, revisar para produção
