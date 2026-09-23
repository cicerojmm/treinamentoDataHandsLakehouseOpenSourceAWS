# Plataforma de Dados Open Source

Plataforma de dados moderna em Kubernetes usando ferramentas open source.

## Arquitetura

```
Airbyte → Airflow → MinIO → dbt + Trino → API (DuckDB) → Metabase
                                        ↘ Spark + Iceberg
```

Componentes de suporte: Grafana, OpenMetadata, Great Expectations

## Pré-requisitos

**Local (kind):**
- Docker 24.x+
- kind 0.23.x+
- kubectl 1.29.x+
- Helm 3.14.x+

**EKS (adicional):**
- AWS CLI v2, configurado com credenciais válidas (`aws sts get-caller-identity`)
- Terraform 1.5+

Numa máquina Ubuntu nova (notebook novo ou EC2 recém-criada), instale
tudo isso de uma vez com `bash scripts/ec2-bootstrap.sh`.

## Quick Start (Local)

Funciona igual em qualquer máquina — notebook, EC2, qualquer lugar —
desde que o repo esteja clonado ali:

```bash
git clone https://github.com/cicerojmm/treinamentoDataHandsLakehouseOpenSourceAWS.git
cd treinamentoDataHandsLakehouseOpenSourceAWS

# git pull + sobe o cluster kind + ArgoCD + espera tudo ficar Synced/Healthy
make run-local
```

Comandos individuais (o que `make run-local` já orquestra):

```bash
# Subir o cluster e ArgoCD (sem git pull nem espera de health)
make bootstrap-local

# Acessar UI do ArgoCD (http://localhost:8080)
make argocd-ui

# Obter senha do admin
make argocd-password

# Destruir tudo e recomeçar
make destroy-local
```

Só `ArgoCD` (porta 8080) e `Airbyte` (porta 8001) têm porta mapeada no
`infra/clusters/local/kind-config.yaml`. Para as outras UIs (Airflow,
Metabase, Trino, Grafana, OpenMetadata), use `kubectl port-forward`.

### Rodando numa máquina remota (ex: EC2)

Este projeto já teve uma instância dedicada para isso (`data-platform-os`,
`t3a.2xlarge`, região `us-east-2`), hoje parada e sem Elastic IP — o IP
público muda a cada `start`. Para reativar e usar:

```bash
# 1. Iniciar a instância e pegar o IP público atual
aws ec2 start-instances --region us-east-2 --instance-ids i-0de2b9ce8d797f0ac
aws ec2 describe-instances --region us-east-2 --instance-ids i-0de2b9ce8d797f0ac \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text

# 2. Entrar por SSH e rodar make run-local lá dentro
ssh -i ~/caminho/para/sua-chave.pem ubuntu@<ip-retornado>
cd treinamentoDataHandsLakehouseOpenSourceAWS && make run-local
```

Por decisão do projeto, **não abrimos o Security Group** para expor as
UIs na internet. Acesse via túnel SSH, numa outra aba (depois do
`make run-local` terminar):

```bash
ssh -i ~/caminho/para/sua-chave.pem \
  -L 8080:localhost:8080 -L 8001:localhost:8001 \
  ubuntu@<ip-da-instancia>
```

Para desligar a instância e economizar quando não estiver em uso:
```bash
aws ec2 stop-instances --region us-east-2 --instance-ids i-0de2b9ce8d797f0ac
```

## Quick Start (EKS)

Cria infraestrutura real na AWS (~US\$ 490/mês: EKS + 4x t3.large + NAT
+ 6 LoadBalancers). Ver `specs/SPEC-014-terraform-eks.md` e
`specs/SPEC-015-overlays-eks.md` para o detalhamento.

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

Trino e MinIO não têm LoadBalancer (decisão do projeto) — acesse via
`kubectl port-forward`, com o contexto `data-platform-eks`:
```bash
kubectl --context=data-platform-eks port-forward -n query-engine svc/trino 8080:8080
kubectl --context=data-platform-eks port-forward -n data-platform svc/minio-eks-console 9090:9090
```

A conexão do Airbyte (Postgres de exemplo → bucket `bronze`) é manual,
veja `docs/runbooks/airbyte-eks-setup.md`.

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
code/                        # Código próprio (dbt, airflow-dags, api-service, metabase)
scripts/                     # Scripts de bootstrap/deploy (run-local, ensure-images-eks, ...)
docs/runbooks/               # Passo a passo de configurações manuais (ex: Airbyte)
```

## GitOps

Todas as mudanças são feitas via Git. O ArgoCD sincroniza automaticamente
os recursos definidos em `apps/local/` (ou `apps/eks/`) para o cluster.

Nunca use `kubectl apply` diretamente — sempre via commit + push. A
única exceção é o bootstrap do próprio ArgoCD: instalar o ArgoCD via
Helm e aplicar o `app-of-apps` uma primeira vez (é o que `make
run-local`/`make bootstrap-eks` fazem) — depois disso, o próprio
ArgoCD passa a gerenciar tudo, inclusive a si mesmo.
