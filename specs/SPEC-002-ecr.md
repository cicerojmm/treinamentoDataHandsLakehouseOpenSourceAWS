# SPEC-002: Repositórios ECR + Autenticação Local

**Fase do projeto:** 0 — Bootstrap
**Pré-requisitos:** SPEC-001 (cluster local + ArgoCD funcionando)
**Bloqueia:** SPEC-008 (dbt), SPEC-010 (API), SPEC-011 (CI/CD), SPEC-012 (Spark), SPEC-005 (Airflow, imagem com DAGs)
**Status:** Specify

---

## 1. Contexto
Toda imagem de código próprio (Airflow com DAGs, dbt, API, Spark jobs) é
publicada no ECR, inclusive para uso no cluster local `kind` — não há
`kind load docker-image` neste projeto (decisão fechada no CLAUDE.md).
Este spec cria os repositórios ECR e resolve a autenticação do cluster
local para puxar imagens de lá.

## 2. Pré-requisitos de ambiente
- AWS CLI configurado com credenciais de uma conta/dev account
- Permissão IAM para criar repositórios ECR (`ecr:CreateRepository` e afins)

## 3. Arquivos a criar
```
infra/terraform/modules/ecr/
├── main.tf
├── variables.tf
└── outputs.tf
infra/terraform/envs/shared/
└── ecr.tf                      # instancia o módulo para os 4 repos
bootstrap/ecr-auth/
├── local-ecr-secret.sh          # script que gera/atualiza o imagePullSecret local
└── cronjob-refresh-token.yaml   # opcional: renovação automática do token (12h)
```

## 4. Especificação técnica

### 4.1 Repositórios (Terraform, módulo `ecr`)
Um repositório por serviço (decisão fechada), nomeados:
- `data-platform/airflow-dags`
- `data-platform/dbt-project`
- `data-platform/api-service`
- `data-platform/spark-jobs`

Cada repositório com:
- `image_tag_mutability = IMMUTABLE` (tags por Git SHA nunca são sobrescritas)
- Lifecycle policy: manter últimas 20 imagens, expirar o resto
- Scan on push habilitado (segurança básica gratuita do ECR)

### 4.2 Autenticação do cluster local
Como o `kind` não tem IRSA (isso só existe no EKS), a autenticação local
usa um `Secret` do tipo `kubernetes.io/dockerconfigjson`, gerado via:
```bash
aws ecr get-login-password --region <regiao> | \
  kubectl create secret docker-registry ecr-pull-secret \
  --docker-server=<account-id>.dkr.ecr.<regiao>.amazonaws.com \
  --docker-username=AWS \
  --docker-password-stdin \
  -n <namespace>
```
Isso precisa ser repetido a cada 12h (expiração do token). O
`cronjob-refresh-token.yaml` automatiza isso rodando dentro do próprio
cluster (usando uma ServiceAccount com credenciais AWS via Secret, ou
via `kubectl` com IAM externo — detalhar no Plan).

O secret `ecr-pull-secret` precisa existir em cada namespace que roda
imagens do ECR: `orchestration`, `data-platform` (Spark), e onde a API
for implantada.

## 5. Ordem de execução esperada
```
1. terraform apply (cria os 4 repositórios ECR)
2. Rodar local-ecr-secret.sh para cada namespace relevante
3. Aplicar cronjob-refresh-token.yaml para renovação automática
```

## 6. Critério de Aceite
1. `aws ecr describe-repositories` lista os 4 repositórios criados
2. `kubectl get secret ecr-pull-secret -n orchestration` existe e não está vazio
3. Um `Pod` de teste referenciando uma imagem pública do ECR (ex: push manual de uma imagem `hello-world` para `data-platform/api-service`) sobe com sucesso usando `imagePullSecrets: [ecr-pull-secret]`
4. Após 12h, o cronjob de refresh mantém o pull funcionando sem intervenção manual (validar rodando `kubectl rollout restart` de um deployment de teste após a expiração)

## 7. Rollback / Recuperação
`terraform destroy` no módulo ECR remove os repositórios (cuidado: perde
imagens publicadas). Para o secret, basta deletar e re-executar o script.

## 8. Fora de escopo
- Configuração de IRSA para o EKS (isso é tratado no SPEC-016/017, onde
  o pull passa a ser via IAM Role, sem secret estático)
- Push de imagens reais (isso acontece no SPEC-011, CI/CD)

## 9. Decisões assumidas (revisar se necessário)
- Região AWS: assumindo a mesma região que será usada no EKS mais tarde
  (definir e manter consistente — impacta o SPEC-016)
- Renovação do token via CronJob rodando `aws ecr get-login-password`
  dentro do cluster: alternativa mais simples é rodar manualmente durante
  o desenvolvimento inicial e só automatizar depois — decidir no Plan
