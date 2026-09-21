# SPEC-015: Overlays EKS (Apps + Storage + LoadBalancer)

**Fase do projeto:** 4 — Migração para EKS
**Pré-requisitos:** SPEC-014 (cluster EKS existente), todos os specs locais (001-013) validados
**Bloqueia:** nenhum — spec final de migração
**Status:** Specify (completo)

---

## 1. Contexto
Adapta todos os componentes já validados localmente para rodar no EKS,
trocando apenas configuração declarativa (StorageClass, Service type,
resources) — sem mudança de código.

### Decisões fechadas:
- **Sem domínio próprio** — acesso via IP público do LoadBalancer
- **Sem TLS** — ambiente de testes, HTTP apenas
- **MinIO standalone** — mesmo modo do ambiente local
- **Sem External Secrets** — manter secrets estáticos (ambiente de testes)
- **LoadBalancer simples** — NLB para serviços que precisam de acesso externo

## 2. Arquivos a criar
```
apps/eks/                           # Applications ArgoCD para EKS
├── app-of-apps.yaml
├── minio-operator-app.yaml
├── minio-tenant-app.yaml
├── trino-app.yaml
├── airflow-app.yaml
├── airflow-postgres-app.yaml
├── airbyte-app.yaml
├── airbyte-postgres-app.yaml
├── airbyte-sample-source-app.yaml
├── hive-metastore-app.yaml
├── hive-metastore-postgres-app.yaml
├── metabase-app.yaml
├── api-service-app.yaml
├── kube-prometheus-stack-app.yaml
├── openmetadata-app.yaml
├── openmetadata-postgres-app.yaml
└── opensearch-app.yaml

charts/*/values-eks.yaml             # Values específicos para EKS (onde necessário)
```

## 3. Especificação técnica

### 3.1 Storage
- StorageClass: `gp3` (criada no SPEC-014)
- Todos os PVCs que usavam `local-path` passam a usar `gp3`
- MinIO, Postgres (4 instâncias) usam volumes EBS

### 3.2 Acesso Externo (LoadBalancer)
Serviços expostos via LoadBalancer (NLB):

| Serviço | Porta | Tipo |
|---------|-------|------|
| Airbyte UI | 8001 | LoadBalancer |
| Airflow UI | 8080 | LoadBalancer |
| Metabase | 3000 | LoadBalancer |
| Grafana | 3001 | LoadBalancer |
| OpenMetadata | 8585 | LoadBalancer |
| API | 8000 | LoadBalancer |
| Trino | 8080 | ClusterIP (interno) |
| MinIO | 9000/9001 | ClusterIP (interno) |

### 3.3 Diferenças dos Values EKS vs Local

| Componente | Local | EKS |
|------------|-------|-----|
| Service type | NodePort | LoadBalancer |
| StorageClass | local-path | gp3 |
| Resources | limits baixos | limits ajustados |
| Replicas | 1 | 1 (testes) |

### 3.4 ECR Pull
- Nodes já têm permissão via IAM Role (AmazonEC2ContainerRegistryReadOnly)
- Não precisa de imagePullSecrets no EKS

### 3.5 MinIO no EKS
- Mesmo Tenant config do local
- StorageClass: gp3
- Modo: standalone (1 node, 1 drive)
- Buckets: bronze, warehouse, airbyte-storage

## 4. Critério de Aceite

1. `kubectl get applications -n argocd` mostra todas as apps Synced/Healthy
2. Todos os pods Running em seus namespaces
3. Serviços acessíveis via IP do LoadBalancer
4. Pipeline ponta a ponta funciona (Airbyte → Airflow → dbt → API)
5. MinIO buckets acessíveis via Trino

## 5. Fora de escopo
- DNS / TLS (sem domínio)
- External Secrets (secrets estáticos para testes)
- Autoscaling de nodes
- Backups automatizados

## 6. Rollback
```bash
kubectl delete applications -n argocd -l environment=eks
```

## 7. Comandos de validação
```bash
kubectl get applications -n argocd
kubectl get pods -A | grep -v kube-system
kubectl get svc -A -o wide | grep LoadBalancer
```
