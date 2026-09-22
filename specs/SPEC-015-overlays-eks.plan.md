# SPEC-015: Overlays EKS — Plano de Implementação

**Gerado em:** 2026-09-22
**Status:** Aprovado — decisões D1=A, D2=A, D3=A (2026-09-22)

---

## Pré-requisitos verificados

- [x] SPEC-014 aplicado: cluster `data-platform-eks` (K8s 1.32, 3x t3.large), StorageClass `gp3` default, EBS CSI com IRSA
- [x] Node role com `AmazonEC2ContainerRegistryReadOnly` (pull do ECR sem imagePullSecret)
- [x] Imagens customizadas existentes no ECR (us-east-2):
  - `data-platform/airflow-dags:v20260921163358` (DAGs + dbt + Cosmos)
  - `data-platform/api-service:v20260918204856`
  - `data-platform/metabase:v20260919110500`
- [x] `apps/eks/` já existe (14 Applications, usadas no cluster EKS anterior) — o trabalho é **corrigir gaps**, não criar do zero
- [x] Repositório GitHub `cicerojmm/treinamentoDataHandsLakehouseOpenSourceAWS` público/acessível pelo ArgoCD; `main` sincronizado com `origin/main`

### Estado atual de `apps/eks/` vs spec (gaps encontrados na leitura)

| # | Gap | Arquivo | Impacto |
|---|-----|---------|---------|
| G1 | Trino EKS sem catálogos `hive_bronze` e `postgres_source` (existem só em `charts/trino/values-local.yaml`) | `apps/eks/trino-app.yaml` | **DAG dbt_movielens falha** (usa `hive_bronze.movielens.*`) |
| G2 | Trino EKS usa `default-warehouse-dir=s3://gold/warehouse`; local e CLAUDE.md usam `s3://warehouse` | `apps/eks/trino-app.yaml` | Tabelas Iceberg no bucket errado; API lê `warehouse` |
| G3 | Nenhum Service `LoadBalancer` — tudo ClusterIP/NodePort; nodes estão em subnets privadas, NodePort inacessível | vários | Critério 3 falha |
| G4 | Criação de buckets (`bronze`, `warehouse`, `silver`, `gold`, `airbyte-storage`) só existe como Job local apontando para `minio-local-hl` | `bootstrap/minio/create-buckets-job.yaml` | Airbyte/Trino/API sem buckets |
| G5 | DB `iceberg_catalog` + tabelas JDBC criados por script `kubectl exec` (`bootstrap/trino/setup-jdbc-catalog.sh`) | — | Catálogo `iceberg` do Trino quebra |
| G6 | Dados Movielens do sample source (`bootstrap/sample-data/*.sql`) carregados manualmente; `postgres_source` local aponta para DB `movielens`, mas o Postgres EKS cria DB `sample` (user `sample`) | `charts/postgres-eks/sample-source-postgres.yaml` | Pipeline E2E sem dados |
| G7 | Apps sem `sync-wave` (metabase, api, opensearch, openmetadata, kube-prometheus-stack, servicemonitors) sobem antes de MinIO/Postgres; `servicemonitors` depende de CRDs do Prometheus | `apps/eks/*.yaml` | Syncs com erro até retry; ServiceMonitor falha sem CRD |
| G8 | Referências a `ecr-pull-secret` (Airflow `registry.secretName`, Metabase, API base) — secret não existe no EKS | `apps/eks/airflow-app.yaml`, `charts/metabase-eks/metabase.yaml`, `code/api-service/k8s-eks/` | Só warning `FailedToRetrieveImagePullSecret`; pull funciona via node role |
| G10 | `lakehouse-api-secret` não é criado no EKS (removido do kustomization base em 0d3f048) e tinha credenciais MinIO erradas (`admin/admin123`) | `code/api-service/k8s-eks/` | API em `CreateContainerConfigError` |
| G11 | Conexão `trino_default` usada pela DAG não está definida em nenhum lugar | `apps/eks/airflow-app.yaml` | Tasks `create_*_table` falham |
| G12 | `profiles.yml` do dbt usa default `trino.data-platform`; no EKS o Trino está em `query-engine` | `apps/eks/airflow-app.yaml` (env `DBT_TRINO_HOST`) | dbt não conecta |
| G9 | Arquivos do spec (`airflow-postgres-app.yaml`, etc. separados) não batem com a estrutura real (`postgres-all-app.yaml` agrupado) | `specs/SPEC-015-overlays-eks.md` | Documentação desatualizada |

---

## Decisões (resolvidas)

### D1 — Acesso externo (G3)
Nodes em subnets privadas → só LoadBalancer (ou port-forward) alcança os serviços.

| Opção | Custo extra/mês | Prós | Contras |
|---|---|---|---|
| **A. 1 NLB por serviço (como no spec)** — 6 NLBs + ArgoCD | ~$115 (7 × ~$16) | Fiel ao spec, zero componente novo | Custo alto p/ ambiente de testes; 7 hostnames |
| B. 1 NLB + ingress-nginx, roteamento por path/porta | ~$16 | Barato, 1 endpoint | Componente novo; apps com base-path (Airflow, Airbyte, Grafana) exigem config extra; sem domínio → roteamento por path |
| C. Sem LB — `kubectl port-forward` | $0 | Mais barato | Viola critério 3 do spec (exigiria alterar o spec) |

**Recomendação:** A, restrito aos 6 serviços do spec (ArgoCD via port-forward). Usar o controller in-tree do EKS com annotation `service.beta.kubernetes.io/aws-load-balancer-type: nlb` + `aws-load-balancer-scheme: internet-facing` — sem AWS Load Balancer Controller (evita IRSA/Terraform extra).

### D2 — Setup de dados/infra (G4, G5, G6)
| Opção | Prós | Contras |
|---|---|---|
| **A. Jobs Kubernetes versionados no Git, sincronizados pelo ArgoCD** (hook `PostSync`/sync-wave) | Respeita "nada manual no cluster"; reprodutível em cada recriação | Mais YAML |
| B. Manter scripts `kubectl exec` do bootstrap, adaptados para EKS | Rápido | Viola regra de mudanças via Git; passo manual a cada recriação |

**Recomendação:** A.

### D3 — Configuração da conexão Airbyte (Postgres sample → MinIO bronze)
| Opção | Prós | Contras |
|---|---|---|
| **A. Manual via UI + runbook `docs/runbooks/airbyte-eks-setup.md`** | Simples; já foi feito assim no local (SPEC-006) | Passo manual após cada recriação |
| B. Job que chama a API do Airbyte | Automatizado | API do Airbyte 1.7 muda entre versões; frágil |

**Recomendação:** A.

---

## Tarefas

> Todas as mudanças via Git → push → ArgoCD sync. Única exceção: bootstrap do ArgoCD (Tarefa 1), que não pode ser feito por ele mesmo.

### Tarefa 1: Bootstrap do ArgoCD no EKS
**Dependência:** SPEC-014 aplicado
```bash
aws eks update-kubeconfig --name data-platform-eks --region us-east-2
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace \
  -f bootstrap/argocd/install-values.yaml --wait --timeout 10m
```
Validação: `kubectl get pods -n argocd` (todos Running)

### Tarefa 2: Corrigir catálogos do Trino (G1, G2)
**Arquivo:** `apps/eks/trino-app.yaml`
- `iceberg.jdbc-catalog.default-warehouse-dir=s3://warehouse`
- Adicionar `hive_bronze` (Hive file metastore em `s3://bronze/metastore`, endpoint `minio-eks-hl`)
- Adicionar `postgres_source` → `sample-source-postgres.ingestion:5432`, DB/usuário conforme Tarefa 4
Validação: `helm template` do chart 0.31.0 com os values → conferir 3 catálogos no ConfigMap

### Tarefa 3: Jobs de setup do MinIO e do catálogo Iceberg (G4, G5)
**Arquivos novos:**
- `charts/minio-eks-setup/kustomization.yaml`
- `charts/minio-eks-setup/create-buckets-job.yaml` — `mc mb` para `bronze`, `warehouse`, `silver`, `gold`, `airbyte-storage` em `minio-eks-hl.data-platform:9000` (imagem `quay.io/minio/mc` com tag fixa, não `latest`)
- `charts/postgres-eks/iceberg-catalog-init-job.yaml` — `CREATE DATABASE iceberg_catalog` + tabelas `iceberg_tables`, `iceberg_namespace_properties` (SQL de `bootstrap/trino/setup-jdbc-catalog.sh`), idempotente
- `apps/eks/minio-eks-setup-app.yaml` — sync-wave `3`
Validação: `kubectl kustomize charts/minio-eks-setup` e `kubectl kustomize charts/postgres-eks`

### Tarefa 4: Carga dos dados Movielens no sample source (G6)
**Arquivos:**
- `charts/postgres-eks/sample-source-postgres.yaml` — `POSTGRES_DB: movielens`; montar `movielens-schema.sql` + `movielens-data.sql` via ConfigMap em `/docker-entrypoint-initdb.d`
- `charts/postgres-eks/kustomization.yaml` — `configMapGenerator` com os 2 SQLs (copiados para `charts/postgres-eks/sample-data/`, pois kustomize não lê fora do diretório)
Tamanho verificado: schema 1 KB + dados 7 KB — cabe em ConfigMap. Init scripts só rodam com PVC vazio (cluster novo).
Validação: `kubectl kustomize charts/postgres-eks`

### Tarefa 5: Services LoadBalancer (G3) — conforme D1
**Arquivos:**
| Serviço | Arquivo | Mudança |
|---|---|---|
| Airbyte webapp (8001→80) | `apps/eks/airbyte-app.yaml` | `webapp.service.type: LoadBalancer` + annotations NLB (remover `nodePort`) |
| Airflow apiServer (8080) | `apps/eks/airflow-app.yaml` | `apiServer.service.type: LoadBalancer` + `annotations` |
| Metabase (3000) | `charts/metabase-eks/metabase.yaml` | Service → LoadBalancer |
| Grafana (3001→80) | novo `charts/observability/values-eks.yaml` + `apps/eks/kube-prometheus-stack-app.yaml` passa a usar `values-local.yaml` + `values-eks.yaml` | `grafana.service.type: LoadBalancer`, `port: 3001` |
| OpenMetadata (8585) | novo `charts/openmetadata/values-eks.yaml` + `apps/eks/openmetadata-app.yaml` | `service.type: LoadBalancer` |
| API (8000) | `code/api-service/k8s-eks/kustomization.yaml` | patch `/spec/type: LoadBalancer` + annotations |

Annotations padrão:
```yaml
service.beta.kubernetes.io/aws-load-balancer-type: nlb
service.beta.kubernetes.io/aws-load-balancer-scheme: internet-facing
```
Trino e MinIO permanecem ClusterIP.
Validação: `kubectl kustomize` nos diretórios Kustomize; `helm template` nos charts com values alterados

### Tarefa 5b: Secret da API e conexões do Airflow (G10, G11, G12)
- `code/api-service/k8s-eks/secret.yaml` (novo, `minio/minio123`) + incluído no kustomization EKS
- `apps/eks/airflow-app.yaml` → `env`: `AIRFLOW_CONN_TRINO_DEFAULT=trino://admin@trino.query-engine.svc.cluster.local:8080/`, `DBT_TRINO_HOST=trino.query-engine.svc.cluster.local`
Validação: `kubectl kustomize code/api-service/k8s-eks`; `helm template` do Airflow contém `AIRFLOW_CONN_TRINO_DEFAULT`

### Tarefa 6: Sync-waves e remoção de `ecr-pull-secret` (G7, G8)
**Arquivos:** `apps/eks/*.yaml`
- Ordem: `minio-operator`(1) → `minio-tenant`(2) → `postgres-all`, `minio-eks-setup`(3) → `hive-metastore`(4) → `kube-prometheus-stack`(5) → `airflow`(6), `servicemonitors`(6) → `airbyte-prereqs`(7) → `airbyte`, `opensearch`(8) → `trino`, `openmetadata`(9) → `metabase`, `lakehouse-api`(10)
- Remover `registry.secretName` (Airflow), `imagePullSecrets` em `charts/metabase-eks/metabase.yaml`, e patch `remove /spec/template/spec/imagePullSecrets` em `code/api-service/k8s-eks/kustomization.yaml` (base local intacta)
Validação: `grep -rn ecr-pull-secret apps/eks charts/metabase-eks code/api-service/k8s-eks` → vazio (exceto base local)

### Tarefa 7: Commit, push e app-of-apps
**Dependência:** Tarefas 1–6
```bash
git add apps/eks charts code/api-service/k8s-eks
git commit -m "feat(SPEC-015): overlays EKS — LB, catálogos Trino, jobs de setup"
git push origin main
kubectl apply -n argocd -f apps/eks/app-of-apps.yaml   # bootstrap único do app-of-apps
```
Validação: `kubectl get applications -n argocd -w` até todas Synced

### Tarefa 8: Acompanhar sync e corrigir falhas
**Dependência:** Tarefa 7
- Acompanhar por wave; correções sempre via commit + push (nunca `kubectl edit`)
- Checar pull das imagens ECR: `kubectl get pods -A | grep -E 'ImagePull|ErrImage'` → vazio
Validação: `kubectl get applications -n argocd` (Synced/Healthy)

### Tarefa 9: Runbook Airbyte + execução E2E (D3)
**Arquivo:** `docs/runbooks/airbyte-eks-setup.md` — criar source Postgres (`sample-source-postgres.ingestion`), destination S3 (MinIO `bronze`, Parquet), connection
- Rodar sync no Airbyte → trigger DAG `dbt_movielens` no Airflow → consultar API
Validação: `curl -H "X-API-Key: ..." http://<api-lb>:8000/...` retorna dados gold

### Tarefa 10: Atualizar o spec (G9)
**Arquivo:** `specs/SPEC-015-overlays-eks.md` — seção 2 com a estrutura real de `apps/eks/`, sample source e setup jobs.

---

## Ordem de execução
```
T1 (ArgoCD) ─┐
T2, T3, T4, T5, T6 (edições, paralelas) ─┤
                                         ↓
                            T7 (push + app-of-apps)
                                         ↓
                            T8 (sync / correções)
                                         ↓
                            T9 (Airbyte + E2E) → T10
```

---

## Riscos identificados

| Risco | Prob. | Impacto | Mitigação |
|---|---|---|---|
| Capacidade: 3x t3.large (~21 GiB alocáveis, 35 pods/node com VPC CNI) para Airbyte + Airflow + OpenMetadata + OpenSearch + Prometheus | Média | Alto | `kubectl top nodes` após sync; se `Pending` por CPU/mem/pods → subir `node_desired_size` p/ 4 via Terraform |
| NLB não provisiona (subnet tag / controller in-tree) | Baixa | Alto | Subnets públicas têm `kubernetes.io/role/elb=1` (SPEC-014); checar `kubectl describe svc` |
| initdb não roda se o PVC já tiver dados | Baixa | Médio | Cluster recriado com volumes novos; se necessário, apagar PVC do sample source |
| Airbyte 1.7.8 com storage S3 → MinIO (já teve várias iterações de fix) | Média | Alto | Manter values validados no cluster anterior; só mudar Service |
| Ordem de subida: Trino antes do DB `iceberg_catalog` | Média | Médio | Sync-waves (T6) + Job idempotente em wave 3 |
| Custo sobe ~$115/mês com 7 NLBs (opção D1-A) | Certa | Médio | Destruir cluster quando não estiver em uso |
| Sync-waves no app-of-apps ordenam a criação, mas o ArgoCD não espera a Application filha ficar Healthy (health de Application desabilitado por padrão) | Certa | Baixo | Jobs com retry/wait (`backoffLimit`, loop de espera); selfHeal re-sincroniza |
| Credenciais estáticas em Git (minio123, hive123...) | Certa | Baixo | Aceito no spec (sem External Secrets, ambiente de testes) |

---

## Comandos de validação básica (pós-implement)

```bash
kubectl get applications -n argocd
kubectl get pods -A | grep -vE 'Running|Completed'
kubectl get pods -A | grep -E 'ImagePull|ErrImage'           # esperado: vazio
kubectl get svc -A | grep LoadBalancer                        # 6 serviços com EXTERNAL-IP
kubectl exec -n query-engine deploy/trino-coordinator -- trino --execute "SHOW CATALOGS"
kubectl run mc --rm -it --restart=Never -n data-platform --image=quay.io/minio/mc -- \
  sh -c "mc alias set m http://minio-eks-hl:9000 minio minio123 && mc ls m"
kubectl top nodes
```

---

## Rollback
```bash
kubectl delete application app-of-apps -n argocd   # cascade remove apps
# ou revert do commit + push
```
NLBs e volumes EBS são removidos junto com Services/PVCs — **deletar apps antes do `terraform destroy`** para não deixar NLB/EBS órfãos (o que aconteceu no cluster anterior).

---

**Aguardando aprovação para prosseguir com `/implement-spec SPEC-015-overlays-eks`**
