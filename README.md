# Plataforma de Dados Open Source

Plataforma de dados moderna em Kubernetes usando ferramentas open source.

## Arquitetura

```
Postgres (sample) → Airbyte → s3://bronze (Parquet raw)
                                  ↓
Airflow → Trino (hive_bronze) → dbt → s3://warehouse (Iceberg)
                                       ├── staging/ (efêmero)
                                       ├── silver/  (tabelas)
                                       └── gold/    (tabelas)
                                  ↓
                      API (FastAPI + DuckDB) ← lê gold
                      Metabase ← conecta via Trino

Grafana + OpenMetadata: observabilidade e governança (transversal)
```

- **Storage:** MinIO (via AIStor) em todos os ambientes, com os buckets
  `bronze`, `warehouse`, `silver`, `gold` e `airbyte-storage`.
- **Catálogo Iceberg (Trino):** JDBC Catalog com PostgreSQL dedicado.
- **Orquestração:** DAG `dbt_movielens` (Airflow + Cosmos) cria as external
  tables no `hive_bronze` e executa o dbt.
- **Deploy:** GitOps com ArgoCD, local (`kind`) ou EKS (Kubernetes 1.36).

## Pré-requisitos

**Local (kind):**
- Docker 24.x+
- kind 0.23.x+
- kubectl 1.29.x+
- Helm 3.14.x+
- AWS CLI v2, configurado com credenciais válidas (`aws sts get-caller-identity`) —
  as imagens customizadas vêm do ECR privado, inclusive no local

**EKS (adicional):**
- Terraform 1.10+

Numa máquina Ubuntu/Debian, o `make run-local` verifica esses
pré-requisitos e, se faltar algum, roda `scripts/ec2-bootstrap.sh` para
instalá-los (também dá para rodá-lo manualmente). Em outros sistemas,
instale à mão.

## Quick Start (Local)

Funciona igual em qualquer máquina — notebook, EC2, qualquer lugar —
desde que o repo esteja clonado ali.

### Máquina Ubuntu nova (sem os pré-requisitos instalados ainda)

```bash
git clone https://github.com/cicerojmm/treinamentoDataHandsLakehouseOpenSourceAWS.git
cd treinamentoDataHandsLakehouseOpenSourceAWS
```

O `make run-local` (abaixo) detecta o que falta e chama
`scripts/ec2-bootstrap.sh`, que instala Docker, kubectl, kind, Helm,
AWS CLI v2 e Terraform. Se quiser instalar antes, rode
`bash scripts/ec2-bootstrap.sh` manualmente. Não é específico de EC2.

Se o Docker for instalado nessa hora, o usuário é adicionado ao grupo
`docker`, mas isso só vale numa sessão nova. O `run-local` avisa e para;
saia e volte a entrar (ou `newgrp docker`) e rode de novo:
```bash
docker ps   # confirma que funciona sem sudo
```

Configure as credenciais da AWS — necessário mesmo no ambiente local,
já que as imagens customizadas (Airflow, Metabase, API) vêm do ECR
privado e `make run-local` cria o `ecr-pull-secret` sozinho a partir
delas:
```bash
aws configure   # ou aws sso login, dependendo de como vocês autenticam
aws sts get-caller-identity
```

Pegue uma licença **AIStor Free** (single-node, gratuita) em
[subnet.min.io](https://subnet.min.io) — desde 2026-09 a MinIO Inc.
trancou pull anônimo das imagens legadas e o servidor exige licença
pra operações S3. `make run-local` cria o Secret
sozinho (nunca commitado no Git) — configure uma vez e esqueça:
```bash
# ~/.bashrc ou ~/.zshrc
export MINIO_LICENSE='<jwt-da-licenca>'
```
Sem a variável, o script cai para checar se o Secret já existe no
cluster (útil se você preferiu criá-lo manualmente antes) e só falha
com instruções se nenhum dos dois estiver disponível.

### Subir a plataforma

```bash
# verifica/instala pré-requisitos + git pull + sobe o cluster kind + ArgoCD
# + espera todas as Applications ficarem Synced/Healthy
make run-local
```

Comandos auxiliares:

```bash
# Acessar UI do ArgoCD (http://localhost:8080)
make argocd-ui

# Obter senha do admin
make argocd-password

# Destruir tudo e recomeçar
make destroy-local
```

Só `ArgoCD` (porta 8080) e `Airbyte` (porta 8001) têm porta mapeada no
`infra/clusters/local/kind-config.yaml`. Para as outras UIs (Airflow,
Metabase, Trino, Grafana, OpenMetadata), use `kubectl port-forward`, ex:
```bash
kubectl port-forward -n orchestration svc/airflow-api-server 8080:8080
kubectl port-forward -n data-platform svc/metabase 3000:3000
kubectl port-forward -n query-engine svc/trino 8081:8080
kubectl port-forward -n observability svc/kube-prometheus-stack-grafana 3001:80
kubectl port-forward -n governance svc/openmetadata 8585:8585
```

### Rodando numa máquina remota (ex: EC2)

Conecte por SSH, clone o repo e rode `make run-local` lá dentro (seção
"Máquina Ubuntu nova" acima — ele instala o que faltar):
```bash
ssh -i ~/caminho/para/sua-chave.pem ubuntu@<ip-da-instancia>
cd treinamentoDataHandsLakehouseOpenSourceAWS && make run-local
```

Por decisão do projeto, **não abrimos o Security Group** para expor as UIs
na internet. Acesse via túnel SSH, numa outra aba (depois do
`make run-local` terminar):

```bash
ssh -i ~/caminho/para/sua-chave.pem \
  -L 8080:localhost:8080 -L 8001:localhost:8001 \
  ubuntu@<ip-da-instancia>
```

## Quick Start (EKS)

Cria infraestrutura real na AWS (~US\$ 490/mês: EKS + 4x t3.large + NAT
+ 6 LoadBalancers). Ver `specs/SPEC-014-terraform-eks.md` e
`specs/SPEC-015-overlays-eks.md` para o detalhamento.

Pegue uma licença **AIStor Free** (single-node, gratuita) em
[subnet.min.io](https://subnet.min.io) — desde 2026-09 a MinIO Inc.
trancou pull anônimo das imagens legadas e o servidor exige licença pra
operações S3 (mesmo motivo do ambiente local). `make bootstrap-eks`
cria o Secret sozinho (nunca commitado no Git), configure uma vez:

- **Rodando local** (`make bootstrap-eks` na sua máquina): exporte
  `MINIO_LICENSE` no seu `~/.bashrc`/`~/.zshrc`, igual no ambiente local.
- **Rodando via CI** (`infra-bootstrap.yml`, `workflow_dispatch`): adicione
  `MINIO_LICENSE` como um *repository secret* do GitHub
  (`Settings → Secrets and variables → Actions → New repository secret`).
  O job `deploy` já repassa `secrets.MINIO_LICENSE` pro `make
  deploy-argocd-eks`.

Sem a variável (nem o secret do GitHub), o bootstrap cai para checar se
o Secret já existe no cluster — útil se um cluster novo ainda tem o
Secret de uma criação manual anterior — e só falha com instruções se
nenhum dos dois estiver disponível. Pra criar manualmente:
```bash
aws eks update-kubeconfig --name data-platform-eks --region us-east-2 --alias data-platform-eks
kubectl --context=data-platform-eks create namespace data-platform --dry-run=client -o yaml | kubectl --context=data-platform-eks apply -f -
kubectl --context=data-platform-eks create secret generic minio-eks-license -n data-platform \
  --from-literal=minio.license='<jwt-da-licenca>'
```

```bash
# terraform apply -> garante imagens customizadas no ECR -> ArgoCD ->
# app-of-apps -> espera tudo Synced/Healthy (~20-30 min, pede confirmação)
make bootstrap-eks

# Pular a confirmação interativa (ex: uso em CI):
make bootstrap-eks CONFIRM=yes
```

Comandos auxiliares:

```bash
make plan-eks              # só terraform plan, não cria nada
make urls-eks               # lista as URLs dos LoadBalancers (Airflow, Airbyte, Metabase, OpenMetadata, Grafana, API)
make argocd-password-eks    # senha do admin do ArgoCD
make argocd-ui-eks          # port-forward para a UI do ArgoCD
make wait-eks                # só espera as Applications ficarem Synced/Healthy

# Remove as Applications do ArgoCD primeiro (evita NLB/EBS órfãos)
# e só depois destrói a infra:
make destroy-eks
```

Os 6 LoadBalancers (NLB, `internet-facing`, HTTP, sem TLS) expõem Airflow,
Airbyte, Metabase, OpenMetadata, Grafana e API publicamente; a proteção é
só o login de cada ferramenta (e o `X-API-Key` na API). Restrinja o acesso
por IP se for deixar o cluster no ar.

Trino e MinIO não têm LoadBalancer (decisão do projeto) — acesse via
`kubectl port-forward`, com o contexto `data-platform-eks`:
```bash
kubectl --context=data-platform-eks port-forward -n query-engine svc/trino 8080:8080
kubectl --context=data-platform-eks port-forward -n data-platform svc/minio-eks-console 9090:9090
```

A conexão do Airbyte (Postgres de exemplo → `s3://bronze/movielens/`, em
`full_refresh_overwrite`) é manual; veja `docs/runbooks/airbyte-eks-setup.md`.

### Local x EKS usam contextos `kubectl` diferentes

Não há risco de um comando ir para o cluster errado: o ambiente local
usa o contexto que o `kind` cria (`kind-data-platform-local`), e o EKS
usa o alias `data-platform-eks`, configurado automaticamente pelo
`make bootstrap-eks` (via `aws eks update-kubeconfig --alias
data-platform-eks`). Os targets `*-eks` do Makefile já fixam esse
contexto explicitamente (`kubectl --context=data-platform-eks ...`),
então funcionam mesmo que o contexto atual esteja apontando para o
`kind` local, e vice-versa.

## Estrutura do Repositório

```
specs/                       # Especificações formais (Specify → Plan → Implement → Validate)
infra/clusters/local/        # Configuração do cluster local (kind)
infra/terraform/envs/eks/    # Terraform do cluster EKS (VPC, EKS, IAM/IRSA)
infra/terraform/modules/     # Módulos Terraform reutilizados pelo env eks
bootstrap/argocd/            # Instalação do ArgoCD (local e eks)
apps/local/                  # Applications do ArgoCD (ambiente local)
apps/eks/                    # Applications do ArgoCD (ambiente EKS)
charts/                      # Values/manifests para os charts Helm (local e *-eks)
code/                        # Código próprio (dbt-project, airflow-dags, api-service, metabase)
.github/workflows/           # CI/CD (build/push de imagens + bump do manifesto; infra-bootstrap)
scripts/                     # Scripts de bootstrap/deploy (run-local, ec2-bootstrap, ensure-images-eks, ...)
docs/runbooks/               # Passo a passo de configurações manuais (Airbyte, CI/CD, Metabase, OpenMetadata)
```

## CI/CD

GitHub Actions publica as imagens no ECR (`data-platform/<serviço>`),
com tag igual ao SHA curto do commit (nunca `latest`), e atualiza o
manifesto com essa tag num commit de bump — é isso que o ArgoCD sincroniza.

| Workflow | Dispara em | O que faz |
|---|---|---|
| `airflow-dags.yml` | push em `code/airflow-dags/**` ou `code/dbt-project/**` | roda `dbt parse`, builda e publica a imagem `airflow-dags` (que inclui o dbt) |
| `api-service.yml` | push em `code/api-service/**` | testes, build e publicação da imagem `api-service` |
| `metabase.yml` | push em `code/metabase/**` | build e publicação da imagem `metabase` |
| `infra-bootstrap.yml` | manual (`workflow_dispatch`) | Terraform + imagens + ArgoCD no EKS |

Os três primeiros usam o workflow reutilizável `_build-push-bump.yml`.
Secrets necessários no GitHub: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
e `MINIO_LICENSE` (este só no `infra-bootstrap`). Passo a passo em
`docs/runbooks/cicd-setup.md`.

## GitOps

Todas as mudanças são feitas via Git. O ArgoCD sincroniza automaticamente
os recursos definidos em `apps/local/` (ou `apps/eks/`) para o cluster.

Nunca use `kubectl apply` diretamente — sempre via commit + push. A
única exceção é o bootstrap do próprio ArgoCD: instalar o ArgoCD via
Helm e aplicar o `app-of-apps` uma primeira vez (é o que `make
run-local`/`make bootstrap-eks` fazem) — depois disso, o próprio
ArgoCD passa a gerenciar tudo, inclusive a si mesmo.
