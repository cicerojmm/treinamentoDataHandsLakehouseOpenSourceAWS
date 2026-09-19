# SPEC-016: Terraform EKS (VPC + Cluster + IAM/IRSA)

**Fase do projeto:** 4 — Migração para EKS
**Pré-requisitos:** nenhum tecnicamente (pode rodar em paralelo à Fase 1-3 local), mas so faz sentido decidir perto da migração real
**Bloqueia:** SPEC-017 (overlays EKS)
**Status:** Specify (incompleto — depende de decisões de negócio/custo)

---

## 1. Contexto
Infraestrutura de nuvem base para migrar a plataforma validada
localmente. Diferente dos specs anteriores, este tem decisões que
dependem de fatores fora do escopo técnico (orçamento, requisitos de
compliance, região de operação) — por isso, o Specify aqui fica
propositalmente incompleto até essas decisões existirem.

## 2. Arquivos a criar
```
infra/terraform/modules/
├── vpc/
├── eks/
└── iam-irsa/
infra/terraform/envs/eks-prod/
├── main.tf
├── variables.tf
└── terraform.tfvars
```

## 3. Especificação técnica (parcial)

### 3.1 VPC
- Subnets públicas + privadas em múltiplas AZs (número a definir)
- NAT Gateway (um por AZ para HA, ou um único para reduzir custo —
  trade-off a decidir)

### 3.2 EKS
- Node groups: separar em pelo menos 2 grupos — um para workloads
  gerais (Airflow, Trino, MinIO, API) e um para Spark (maior memória)
- Autoscaling configurado (Cluster Autoscaler ou Karpenter — decidir)

### 3.3 IAM/IRSA
- Roles para: pull de imagens do ECR (substituindo o secret estático
  local do SPEC-002), acesso do MinIO ao EBS, acesso da API/Spark/Trino
  aos recursos necessários

## 4. Critério de Aceite (parcial — completar após decisões)
1. `terraform plan` roda sem erro com as variáveis definitivas
2. `terraform apply` cria o cluster; `aws eks update-kubeconfig` +
   `kubectl get nodes` mostra os node groups esperados
3. Um Pod de teste consegue assumir uma IAM Role via IRSA (validado com
   `aws sts get-caller-identity` de dentro do Pod)

## 5. Fora de escopo
- Deploy de qualquer componente de aplicação (isso é o SPEC-017)

## 6. Decisões pendentes (bloqueantes — resolver antes do Plan)
- **Região AWS** (deve ser a mesma usada no SPEC-002/ECR)
- **CIDR da VPC** e número de AZs
- **Cluster EKS público ou privado** (endpoint access)
- **Tipo de instância dos node groups** (geral e Spark), e se usa Spot
  para algum workload (custo vs confiabilidade)
- **Versão do Kubernetes no EKS**
- **Ferramenta de autoscaling**: Cluster Autoscaler vs Karpenter
- **Orçamento aproximado disponível**, que influencia todas as decisões acima

> Este spec não deve ir para `/plan-spec` até essas perguntas terem
> resposta — gerar um plano de Terraform sem elas resultaria em
> suposições arriscadas para infraestrutura que cria custo e
> permissões reais.
