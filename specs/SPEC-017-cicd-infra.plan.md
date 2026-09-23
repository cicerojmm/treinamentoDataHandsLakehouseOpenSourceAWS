# Plano de Implementação: SPEC-017 (CI/CD de Infraestrutura)

## Pré-requisitos verificados
- SPEC-016 (CI/CD de imagens): Implement concluído. Reusa os mesmos
  GitHub Secrets (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`) e o
  padrão de workflow (`actionlint` para validação).
- SPEC-014 (Terraform EKS): concluído.
- Makefile atual lido por completo (`bootstrap-eks` linhas 97-140) —
  base exata para a extração dos sub-alvos.

## Decisões incorporadas (fechadas com o usuário em 2026-09-23)
1. Sem gate de aprovação antes do `terraform apply` — `workflow_dispatch`
   dispara direto.
2. `terraform destroy` fica fora de escopo, continua manual/local.
3. **3 jobs visíveis e encadeados** no GitHub Actions
   (`terraform → build-images → deploy`), não um `make bootstrap-eks`
   único — exige quebrar o Makefile em sub-alvos reutilizáveis.
4. `make bootstrap-eks` continua existindo como comando único para uso
   manual, chamando os 3 sub-alvos por dentro (comportamento observável
   idêntico ao de hoje).

## Tarefas

### 1. `Makefile` — novos alvos `terraform-apply-eks` e `deploy-argocd-eks`, `bootstrap-eks` reescrito

Extrair de `bootstrap-eks` (linhas 109-112 → `terraform-apply-eks`;
linhas 115-128 → `deploy-argocd-eks`, com `aws eks update-kubeconfig`
adicionado no início — motivo: jobs do GitHub Actions rodam em runners
efêmeros separados, o kubeconfig de um job não chega ao próximo; barato
e idempotente, não muda o comportamento local). `bootstrap-eks` passa a
chamar os 3 sub-alvos (`terraform-apply-eks`, `images-eks` já
existente, `deploy-argocd-eks`) em sequência, mantendo o mesmo prompt de
confirmação e a mesma mensagem final. Adicionar os dois novos nomes na
lista `.PHONY` (linha 1-3).

Conteúdo exato de cada alvo: ver seção "Arquivo 1" do plano de Plan
Mode aprovado (reproduzido abaixo por completo).

```makefile
terraform-apply-eks: check-prereqs-eks
	@echo "==> terraform apply em $(EKS_DIR)..."
	cd $(EKS_DIR) && terraform init -input=false && terraform plan -out=tfplan && terraform apply tfplan
	@echo "==> Configurando kubeconfig (contexto: $(EKS_CONTEXT))..."
	aws eks update-kubeconfig --name $(EKS_CLUSTER_NAME) --region $(AWS_REGION) --alias $(EKS_CONTEXT)

deploy-argocd-eks: check-prereqs-eks
	@echo "==> Configurando kubeconfig (contexto: $(EKS_CONTEXT))..."
	aws eks update-kubeconfig --name $(EKS_CLUSTER_NAME) --region $(AWS_REGION) --alias $(EKS_CONTEXT)
	@echo "==> Instalando/atualizando ArgoCD..."
	helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
	helm repo update
	@if helm status argocd -n argocd --kube-context=$(EKS_CONTEXT) >/dev/null 2>&1; then \
		helm upgrade argocd argo/argo-cd -n argocd --kube-context=$(EKS_CONTEXT) -f bootstrap/argocd/install-values-eks.yaml --wait --timeout 5m; \
	else \
		helm install argocd argo/argo-cd -n argocd --kube-context=$(EKS_CONTEXT) --create-namespace -f bootstrap/argocd/install-values-eks.yaml --wait --timeout 5m; \
	fi
	@echo "==> Aplicando app-of-apps (única exceção não-GitOps: bootstrap do próprio ArgoCD)..."
	kubectl --context=$(EKS_CONTEXT) apply -n argocd -f apps/eks/app-of-apps.yaml
	@echo "==> Aguardando todas as Applications ficarem Synced/Healthy..."
	@KUBE_CONTEXT=$(EKS_CONTEXT) bash scripts/wait-argocd-healthy.sh 1800 15 14
	@echo "==> Verificando buckets do MinIO..."
	@KUBE_CONTEXT=$(EKS_CONTEXT) bash scripts/verify-minio-buckets.sh 300

bootstrap-eks: check-prereqs-eks
	@if [ "$(CONFIRM)" != "yes" ]; then \
		echo "=========================================="; \
		echo "Isso vai criar recursos AWS reais:"; \
		echo "  - EKS + 4x t3.large + NAT Gateway (~US\$$ 375/mês)"; \
		echo "  - 6 LoadBalancers NLB (~US\$$ 115/mês)"; \
		echo "  - terraform apply sozinho leva ~15 min;"; \
		echo "    sync completo do ArgoCD mais ~15-20 min."; \
		echo "=========================================="; \
		read -p "Continuar? [s/N] " confirm; \
		case "$$confirm" in [sS]|[sS][iI][mM]) ;; *) echo "Cancelado."; exit 1;; esac; \
	fi
	@echo "==> [1/3] Terraform apply + kubeconfig..."
	@$(MAKE) terraform-apply-eks
	@echo "==> [2/3] Garantindo imagens customizadas no ECR (build só se faltar)..."
	@$(MAKE) images-eks
	@echo "==> [3/3] ArgoCD + app-of-apps..."
	@$(MAKE) deploy-argocd-eks
	@echo ""
	@echo "=========================================="
	@echo "Bootstrap EKS concluído!"
	@echo "=========================================="
	@$(MAKE) urls-eks
	@echo ""
	@echo "Senha do ArgoCD:  make argocd-password-eks"
	@echo "UI do ArgoCD:     make argocd-ui-eks"
	@echo ""
	@echo "Airbyte configurado? A conexão Postgres -> MinIO é manual:"
	@echo "  docs/runbooks/airbyte-eks-setup.md"
	@echo ""
```

`destroy-eks`, `wait-eks`, `verify-eks`, `urls-eks`,
`argocd-password-eks`, `argocd-ui-eks`, `images-eks`: **sem mudança**.

### 2. `.github/workflows/infra-bootstrap.yml` (novo)

`workflow_dispatch` puro (sem gatilho de push). 3 jobs encadeados via
`needs:`. Sem `permissions: contents: write` (não commita nada de
volta, diferente dos workflows do SPEC-016). `concurrency` no nível do
workflow evita duas execuções completas simultâneas.

```yaml
name: infra-bootstrap

on:
  workflow_dispatch: {}

concurrency:
  group: infra-bootstrap
  cancel-in-progress: false

env:
  AWS_REGION: us-east-2

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.14.1"
      - run: make terraform-apply-eks

  build-images:
    needs: terraform
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}
      - run: make images-eks

  deploy:
    needs: build-images
    runs-on: ubuntu-latest
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}
      - uses: azure/setup-kubectl@v4
      - uses: azure/setup-helm@v4
      - run: make deploy-argocd-eks
```

Cada job instala só as ferramentas que o seu sub-alvo usa (`terraform`:
terraform+aws; `build-images`: aws+docker, já vem no runner;
`deploy`: kubectl+helm+aws). AWS CLI v2 já vem pré-instalado no runner
`ubuntu-latest`, sem step de instalação.

### 3. `docs/runbooks/cicd-setup.md` — nova seção
Adicionar após a seção dos workflows de imagem: como disparar
`infra-bootstrap.yml`, o que esperar de cada um dos 3 jobs, lembrete de
que `terraform destroy` continua manual/local.

### 4. `specs/SPEC-017-cicd-infra.md` — `Status:` → `Plan aprovado`

## Riscos identificados
- **`aws eks update-kubeconfig` duplicado** entre `terraform-apply-eks`
  e `deploy-argocd-eks`: intencional (ver seção de decisões), não é bug.
- **Sem gate de aprovação**: qualquer push com permissão no repo pode
  disparar ~US$430/mês de infra com um clique — risco aceito
  explicitamente pelo usuário.
- **`docker/azure actions de terceiros** (`hashicorp/setup-terraform`,
  `azure/setup-kubectl`, `azure/setup-helm`) são mantidas fora do
  GitHub — risco padrão de supply chain de Actions, mitigado por serem
  as ações oficialmente recomendadas por cada projeto (Hashicorp/Azure),
  mesmo risco que `docker/build-push-action` já aceito no SPEC-016.

## Comandos de validação básica (fim de cada tarefa)
- Tarefa 1: `make -n bootstrap-eks CONFIRM=yes` (dry-run) mostra a
  sequência de sub-`make`s sem executar; `make -n terraform-apply-eks` e
  `make -n deploy-argocd-eks` confirmam que os alvos existem.
- Tarefa 2: `actionlint .github/workflows/infra-bootstrap.yml` — 0
  problemas.
- Execução real do `workflow_dispatch`: fica para depois dos Secrets do
  SPEC-016 estarem configurados (ainda pendente, ação do usuário) — não
  é bloqueante para fechar o Implement deste spec.
