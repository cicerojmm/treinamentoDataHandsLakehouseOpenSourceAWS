# SPEC-014: Terraform EKS — Plano de Implementação

**Gerado em:** 2026-09-21
**Status:** Aguardando aprovação

---

## Pré-requisitos verificados

- [x] SPEC-002 (ECR) implementado — 4 repositórios em us-east-2
- [x] AWS CLI configurada com credenciais válidas
- [x] Terraform instalado (versão 1.5+)
- [x] Estrutura base existe: `infra/terraform/modules/`, `infra/terraform/envs/`

---

## Decisões pendentes

**Nenhuma.** Todas as decisões foram fechadas no spec:
- Região: us-east-2
- Nodes: 2x t3.large On-Demand
- VPC: 2 AZs, 1 NAT Gateway
- Cluster: público, K8s 1.30

---

## Tarefas

### Tarefa 1: Criar módulo VPC
**Arquivos:**
- `infra/terraform/modules/vpc/main.tf`
- `infra/terraform/modules/vpc/variables.tf`
- `infra/terraform/modules/vpc/outputs.tf`

**Especificação:**
- VPC com CIDR 10.0.0.0/16
- 2 subnets públicas (10.0.1.0/24, 10.0.2.0/24) em us-east-2a, us-east-2b
- 2 subnets privadas (10.0.11.0/24, 10.0.12.0/24)
- 1 Internet Gateway
- 1 NAT Gateway (na primeira subnet pública)
- Route tables: pública (IGW) e privada (NAT)
- Tags obrigatórias para EKS:
  - `kubernetes.io/cluster/data-platform-eks = shared`
  - `kubernetes.io/role/elb = 1` (públicas)
  - `kubernetes.io/role/internal-elb = 1` (privadas)

**Validação:**
```bash
cd infra/terraform/modules/vpc
terraform fmt -check
terraform validate
```

---

### Tarefa 2: Criar módulo EKS
**Arquivos:**
- `infra/terraform/modules/eks/main.tf`
- `infra/terraform/modules/eks/variables.tf`
- `infra/terraform/modules/eks/outputs.tf`

**Dependência:** Tarefa 1 (VPC)

**Especificação:**
- Cluster EKS `data-platform-eks`
- Versão Kubernetes: 1.30
- Endpoint público habilitado
- Node Group `general`:
  - Instance type: t3.large
  - Desired: 2, Min: 2, Max: 4
  - Disk: 50GB gp3
  - Subnets: privadas
- Add-ons gerenciados:
  - vpc-cni (latest)
  - coredns (latest)
  - kube-proxy (latest)
  - aws-ebs-csi-driver (latest)
- OIDC Provider para IRSA

**Validação:**
```bash
cd infra/terraform/modules/eks
terraform fmt -check
terraform validate
```

---

### Tarefa 3: Criar módulo IAM/IRSA
**Arquivos:**
- `infra/terraform/modules/iam-irsa/main.tf`
- `infra/terraform/modules/iam-irsa/variables.tf`
- `infra/terraform/modules/iam-irsa/outputs.tf`

**Dependência:** Tarefa 2 (EKS — precisa do OIDC provider URL)

**Especificação:**
- IAM Role para EBS CSI Driver com IRSA:
  - Trust policy: assume role via OIDC do EKS
  - Policy: `AmazonEBSCSIDriverPolicy`
- IAM Role para nodes já inclusa no módulo EKS:
  - `AmazonEKSWorkerNodePolicy`
  - `AmazonEKS_CNI_Policy`
  - `AmazonEC2ContainerRegistryReadOnly`

**Validação:**
```bash
cd infra/terraform/modules/iam-irsa
terraform fmt -check
terraform validate
```

---

### Tarefa 4: Criar environment EKS
**Arquivos:**
- `infra/terraform/envs/eks/main.tf`
- `infra/terraform/envs/eks/variables.tf`
- `infra/terraform/envs/eks/outputs.tf`
- `infra/terraform/envs/eks/terraform.tfvars`
- `infra/terraform/envs/eks/providers.tf`

**Dependência:** Tarefas 1, 2, 3

**Especificação:**
- Chama os 3 módulos (vpc, eks, iam-irsa)
- Provider AWS com região us-east-2
- Backend: local (para simplificar — sem S3/DynamoDB)
- Outputs: cluster_endpoint, cluster_name, kubeconfig_command

**Validação:**
```bash
cd infra/terraform/envs/eks
terraform init
terraform validate
terraform plan -out=tfplan
```

---

### Tarefa 5: Criar StorageClass gp3
**Arquivo:**
- `infra/terraform/envs/eks/storage-class.yaml` (aplicado via null_resource ou kubectl provider)

**Dependência:** Tarefa 4 (cluster criado)

**Especificação:**
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  fsType: ext4
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

**Validação:**
```bash
kubectl get sc gp3
kubectl get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}'
```

---

### Tarefa 6: Aplicar Terraform
**Comando:**
```bash
cd infra/terraform/envs/eks
terraform apply tfplan
```

**Dependência:** Tarefa 4 (plan gerado)

**Tempo estimado:** ~15 minutos

**Validação:**
```bash
aws eks update-kubeconfig --name data-platform-eks --region us-east-2
kubectl get nodes
kubectl cluster-info
```

---

### Tarefa 7: Validar ECR Pull
**Comando:**
```bash
kubectl create -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-ecr-pull
  namespace: default
spec:
  containers:
  - name: test
    image: 093499160510.dkr.ecr.us-east-2.amazonaws.com/data-platform/api-service:latest
    command: ["sleep", "30"]
  restartPolicy: Never
EOF

sleep 10
kubectl get pod test-ecr-pull
kubectl describe pod test-ecr-pull | grep -A5 "Events:"
kubectl delete pod test-ecr-pull
```

**Dependência:** Tarefa 6

---

### Tarefa 8: Validar PVC com EBS
**Comando:**
```bash
kubectl create -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: test-ebs
spec:
  containers:
  - name: test
    image: busybox
    command: ["sleep", "60"]
    volumeMounts:
    - mountPath: /data
      name: test-vol
  volumes:
  - name: test-vol
    persistentVolumeClaim:
      claimName: test-pvc
EOF

sleep 30
kubectl get pvc test-pvc
kubectl get pod test-ebs
kubectl delete pod test-ebs
kubectl delete pvc test-pvc
```

**Dependência:** Tarefa 6

---

## Riscos identificados

| Risco | Probabilidade | Impacto | Mitigação |
|-------|---------------|---------|-----------|
| Limite de VPCs na conta | Baixa | Alto | Verificar `aws ec2 describe-vpcs` antes |
| Limite de EIPs para NAT | Baixa | Alto | Verificar `aws ec2 describe-addresses` |
| Node group não inicia | Média | Alto | Verificar IAM roles e subnet tags |
| EBS CSI não provisiona | Média | Médio | Verificar IRSA trust policy |
| ECR pull falha | Baixa | Médio | Nodes precisam de `AmazonEC2ContainerRegistryReadOnly` |

---

## Comandos de validação básica (pós-implement)

```bash
# 1. Cluster operacional
kubectl get nodes -o wide
# Esperado: 2 nodes em Ready

# 2. Add-ons funcionando
kubectl get pods -n kube-system
# Esperado: coredns, aws-node, kube-proxy rodando

# 3. StorageClass default
kubectl get sc
# Esperado: gp3 com (default)

# 4. OIDC configurado
aws eks describe-cluster --name data-platform-eks --query "cluster.identity.oidc" --region us-east-2
# Esperado: issuer URL presente

# 5. Custo estimado (após 1 dia)
aws ce get-cost-and-usage --time-period Start=$(date -d "yesterday" +%Y-%m-%d),End=$(date +%Y-%m-%d) --granularity DAILY --metrics UnblendedCost --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Elastic Kubernetes Service","Amazon Elastic Compute Cloud - Compute","Amazon Virtual Private Cloud"]}}' --region us-east-1
```

---

## Ordem de execução

```
Tarefa 1 (VPC)
    ↓
Tarefa 2 (EKS) ──→ Tarefa 3 (IAM/IRSA)
    ↓                    ↓
Tarefa 4 (Environment) ←─┘
    ↓
Tarefa 5 (StorageClass)
    ↓
Tarefa 6 (Apply)
    ↓
Tarefa 7 (ECR) ─── Tarefa 8 (EBS) [paralelo]
```

---

## Rollback

```bash
cd infra/terraform/envs/eks
terraform destroy -auto-approve
```

**Atenção:** Isso destrói todos os recursos, incluindo volumes EBS. Se já houver dados, fazer backup antes.

---

**Aguardando aprovação para prosseguir com `/implement-spec SPEC-014`**
