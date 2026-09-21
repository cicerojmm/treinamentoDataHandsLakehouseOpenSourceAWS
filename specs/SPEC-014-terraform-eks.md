# SPEC-014: Terraform EKS (VPC + Cluster + IAM/IRSA)

**Fase do projeto:** 4 — Migração para EKS
**Pré-requisitos:** SPEC-002 (ECR já provisionado em us-east-2)
**Bloqueia:** SPEC-015 (overlays EKS)
**Status:** Specify (completo)

---

## 1. Contexto
Infraestrutura mínima de EKS para ambiente de testes/aprendizado.
Objetivo: rodar a mesma plataforma validada localmente (kind) no EKS
com o menor custo possível, mantendo as mesmas decisões de arquitetura.

### Decisões fechadas:
- **Região:** us-east-2 (mesma do ECR existente)
- **Sem Spot instances** (preferência por estabilidade)
- **Sem domínio próprio** (acesso via IP público/NodePort ou LoadBalancer)
- **MinIO no EKS** (não migrar para S3 nativo)
- **Cluster público** (endpoint acessível pela internet)
- **Custo-alvo:** ~$150-200/mês

## 2. Arquivos a criar
```
infra/terraform/modules/
├── vpc/
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── eks/
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
└── iam-irsa/
    ├── main.tf
    ├── variables.tf
    └── outputs.tf

infra/terraform/envs/eks/
├── main.tf
├── variables.tf
├── outputs.tf
└── terraform.tfvars
```

## 3. Especificação técnica

### 3.1 VPC
- **CIDR:** 10.0.0.0/16
- **AZs:** 2 (us-east-2a, us-east-2b) — mínimo para EKS
- **Subnets públicas:** 10.0.1.0/24, 10.0.2.0/24 (para ALB/NLB)
- **Subnets privadas:** 10.0.11.0/24, 10.0.12.0/24 (para nodes)
- **NAT Gateway:** 1 único (economia de custo, ~$45/mês)
- **Internet Gateway:** 1

### 3.2 EKS
- **Versão Kubernetes:** 1.30 (última estável)
- **Endpoint:** público (para acesso via kubectl sem VPN)
- **Node Group único:**
  - Nome: `general`
  - Tipo: **t3.large** (2 vCPU, 8GB RAM)
  - Quantidade: **2 nodes** (mínimo para distribuir workloads)
  - Capacidade: On-Demand (sem Spot)
  - Disk: 50GB gp3 por node
- **Add-ons gerenciados:**
  - vpc-cni
  - coredns
  - kube-proxy
  - aws-ebs-csi-driver (para PVCs)

### 3.3 IAM/IRSA
- **Node Role:** permissões para ECR pull, EC2, EBS
- **IRSA Roles:**
  - `ebs-csi-controller` — para o EBS CSI Driver criar volumes
  - `cluster-autoscaler` (opcional, para escalar nodes se necessário)

### 3.4 Security Groups
- **Cluster SG:** permite tráfego interno entre nodes
- **Node SG:** permite ingress nas portas NodePort (30000-32767)

### 3.5 Storage Class
- Criar StorageClass `gp3` como default para PVCs

## 4. Estimativa de Custo Mensal

| Recurso | Especificação | Custo/Mês |
|---------|---------------|-----------|
| EKS Control Plane | 1 cluster | $73 |
| EC2 (2x t3.large) | On-Demand | $120 |
| NAT Gateway | 1 | $45 |
| EBS (nodes + PVCs) | ~150GB gp3 | $14 |
| Data Transfer | ~30GB | $3 |
| **Total** | | **~$255/mês** |

### Para reduzir para ~$180/mês:
- Usar t3.medium (1 vCPU, 4GB) em vez de t3.large
- Risco: pode faltar memória para todos os componentes

## 5. Critério de Aceite

1. `terraform init` e `terraform plan` executam sem erro
2. `terraform apply` cria todos os recursos (~15 min)
3. `aws eks update-kubeconfig --name data-platform-eks --region us-east-2` configura kubeconfig
4. `kubectl get nodes` mostra 2 nodes em status Ready
5. `kubectl get sc` mostra StorageClass gp3 como default
6. Pod de teste consegue criar PVC e montar volume EBS
7. Pod de teste consegue fazer pull de imagem do ECR (093499160510.dkr.ecr.us-east-2.amazonaws.com)

## 6. Fora de escopo
- Deploy de aplicações (SPEC-015)
- Ingress Controller / ALB (SPEC-015)
- DNS / TLS (não será usado — acesso via IP)
- CI/CD (SPEC-016)

## 7. Rollback
```bash
terraform destroy -auto-approve
```
Destrói todos os recursos criados. Dados em EBS serão perdidos.

## 8. Comandos de validação
```bash
# Após terraform apply
aws eks update-kubeconfig --name data-platform-eks --region us-east-2
kubectl get nodes
kubectl get sc
kubectl create -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-ecr-pull
spec:
  containers:
  - name: test
    image: 093499160510.dkr.ecr.us-east-2.amazonaws.com/data-platform/api-service:latest
    command: ["sleep", "30"]
  restartPolicy: Never
EOF
kubectl get pod test-ecr-pull
kubectl delete pod test-ecr-pull
```
