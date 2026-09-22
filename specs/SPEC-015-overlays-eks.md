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
- **LoadBalancer simples** — 1 NLB por serviço externo (controller in-tree, annotation `aws-load-balancer-type: nlb`)
- **Setup de dados via Jobs no Git** (buckets, iceberg_catalog, Movielens) — sem `kubectl exec`
- **Conexão Airbyte manual via UI** — documentada em runbook

## 2. Arquivos (estrutura real)
```
apps/eks/                               # Applications ArgoCD para EKS (sync-wave)
├── app-of-apps.yaml
├── minio-operator-app.yaml             # wave 1
├── minio-tenant-app.yaml               # wave 2
├── minio-eks-setup-app.yaml            # wave 3 — Job de criação dos buckets
├── postgres-all-app.yaml               # wave 3 — Postgres de Airflow, Airbyte, Hive, OpenMetadata, sample source
├── hive-metastore-app.yaml             # wave 4
├── kube-prometheus-stack-app.yaml      # wave 5
├── airflow-app.yaml                    # wave 6
├── servicemonitors-app.yaml            # wave 6
├── airbyte-prereqs-app.yaml            # wave 7
├── airbyte-app.yaml                    # wave 8
├── opensearch-app.yaml                 # wave 8
├── openmetadata-app.yaml               # wave 9
├── trino-app.yaml                      # wave 9 — catálogos iceberg, hive_bronze, postgres_source
├── metabase-app.yaml                   # wave 10
└── api-service-app.yaml                # wave 10

charts/postgres-eks/                    # Postgres dedicados + Job iceberg_catalog + dados Movielens (initdb)
charts/minio-eks-setup/                 # Job de buckets (bronze, warehouse, silver, gold, airbyte-storage)
charts/metabase-eks/                    # Metabase + Postgres
charts/airbyte-eks/                     # Secret de storage do Airbyte (MinIO)
charts/observability/values-eks.yaml    # Grafana LoadBalancer
charts/openmetadata/values-eks.yaml     # OpenMetadata LoadBalancer
code/api-service/k8s-eks/               # overlay Kustomize da API (imagem ECR, secret, LoadBalancer)
docs/runbooks/airbyte-eks-setup.md      # configuração manual da conexão Airbyte
```

### Imagens customizadas (ECR, pull via IAM role dos nodes — sem imagePullSecret)
- `data-platform/airflow-dags:v20260921163358`
- `data-platform/api-service:v20260918204856`
- `data-platform/metabase:v20260919110500`

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
