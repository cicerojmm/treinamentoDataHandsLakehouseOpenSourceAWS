.PHONY: bootstrap-local destroy-local argocd-password argocd-ui run-local \
	check-prereqs-eks plan-eks images-eks bootstrap-eks destroy-eks \
	wait-eks urls-eks argocd-password-eks argocd-ui-eks

CLUSTER_NAME := data-platform-local
KIND_CONFIG := infra/clusters/local/kind-config.yaml

# ---------------------------------------------------------------------------
# Local (kind)
# ---------------------------------------------------------------------------

bootstrap-local:
	@echo "==> Verificando se o cluster já existe..."
	@if kind get clusters 2>/dev/null | grep -q "^$(CLUSTER_NAME)$$"; then \
		echo "Cluster $(CLUSTER_NAME) já existe, pulando criação..."; \
	else \
		echo "==> Criando cluster kind..."; \
		kind create cluster --config $(KIND_CONFIG); \
	fi
	@echo "==> Aplicando namespaces..."
	kubectl apply -f bootstrap/namespaces.yaml
	@echo "==> Adicionando repo Helm do ArgoCD..."
	helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
	helm repo update
	@echo "==> Instalando ArgoCD..."
	@if helm status argocd -n argocd >/dev/null 2>&1; then \
		echo "ArgoCD já instalado, atualizando..."; \
		helm upgrade argocd argo/argo-cd -n argocd -f bootstrap/argocd/install-values-local.yaml --wait; \
	else \
		helm install argocd argo/argo-cd -n argocd -f bootstrap/argocd/install-values-local.yaml --wait; \
	fi
	@echo "==> Aguardando ArgoCD server ficar pronto..."
	kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
	@echo "==> Aplicando app-of-apps..."
	kubectl apply -f bootstrap/argocd/app-of-apps.yaml
	@echo ""
	@echo "=========================================="
	@echo "Bootstrap concluído!"
	@echo "=========================================="
	@echo ""
	@echo "Para acessar a UI do ArgoCD:"
	@echo "  make argocd-ui"
	@echo ""
	@echo "Para obter a senha do admin:"
	@echo "  make argocd-password"
	@echo ""

destroy-local:
	@echo "==> Deletando cluster $(CLUSTER_NAME)..."
	kind delete cluster --name $(CLUSTER_NAME)
	@echo "Cluster deletado."

argocd-password:
	@kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d && echo

argocd-ui:
	@echo "Abrindo port-forward para ArgoCD UI em http://localhost:8080"
	@echo "Usuário: admin"
	@echo "Senha: execute 'make argocd-password' em outro terminal"
	@echo ""
	@echo "Pressione Ctrl+C para parar"
	kubectl port-forward svc/argocd-server -n argocd 8080:443

# Roda igual em qualquer maquina (notebook, EC2, qualquer lugar): git pull
# + bootstrap-local + espera tudo ficar Synced/Healthy. Ver scripts/run-local.sh.
run-local:
	@bash scripts/run-local.sh

# ---------------------------------------------------------------------------
# EKS
#
# CONFIRM=yes pula a confirmação interativa do bootstrap-eks/destroy-eks
# (uso em CI ou quando você já sabe o que está fazendo).
# ---------------------------------------------------------------------------

EKS_DIR := infra/terraform/envs/eks
EKS_CLUSTER_NAME := data-platform-eks
EKS_CONTEXT := data-platform-eks
AWS_REGION := us-east-2
CONFIRM ?= no

check-prereqs-eks:
	@echo "==> Verificando pré-requisitos..."
	@for bin in aws kubectl helm terraform docker; do \
		command -v $$bin >/dev/null 2>&1 || { echo "ERRO: '$$bin' não encontrado no PATH."; exit 1; }; \
	done
	@aws sts get-caller-identity >/dev/null || { echo "ERRO: 'aws sts get-caller-identity' falhou — configure suas credenciais AWS."; exit 1; }
	@echo "OK."

plan-eks: check-prereqs-eks
	@echo "==> terraform plan (não cria nada)..."
	cd $(EKS_DIR) && terraform init -input=false && terraform plan

images-eks: check-prereqs-eks
	@AWS_REGION=$(AWS_REGION) bash scripts/ensure-images-eks.sh

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
	@echo "==> [1/6] terraform apply em $(EKS_DIR)..."
	cd $(EKS_DIR) && terraform init -input=false && terraform plan -out=tfplan && terraform apply tfplan
	@echo "==> [2/6] Configurando kubeconfig (contexto: $(EKS_CONTEXT))..."
	aws eks update-kubeconfig --name $(EKS_CLUSTER_NAME) --region $(AWS_REGION) --alias $(EKS_CONTEXT)
	@echo "==> [3/6] Garantindo imagens customizadas no ECR (build só se faltar)..."
	@AWS_REGION=$(AWS_REGION) bash scripts/ensure-images-eks.sh
	@echo "==> [4/6] Instalando/atualizando ArgoCD..."
	helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
	helm repo update
	@if helm status argocd -n argocd --kube-context=$(EKS_CONTEXT) >/dev/null 2>&1; then \
		helm upgrade argocd argo/argo-cd -n argocd --kube-context=$(EKS_CONTEXT) -f bootstrap/argocd/install-values-eks.yaml --wait --timeout 5m; \
	else \
		helm install argocd argo/argo-cd -n argocd --kube-context=$(EKS_CONTEXT) --create-namespace -f bootstrap/argocd/install-values-eks.yaml --wait --timeout 5m; \
	fi
	@echo "==> [5/6] Aplicando app-of-apps (única exceção não-GitOps: bootstrap do próprio ArgoCD)..."
	kubectl --context=$(EKS_CONTEXT) apply -n argocd -f apps/eks/app-of-apps.yaml
	@echo "==> [6/6] Aguardando todas as Applications ficarem Synced/Healthy..."
	@KUBE_CONTEXT=$(EKS_CONTEXT) bash scripts/wait-argocd-healthy.sh 1800 15 14
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

destroy-eks: check-prereqs-eks
	@if [ "$(CONFIRM)" != "yes" ]; then \
		echo "Isso vai remover TODAS as Applications do ArgoCD e destruir o cluster EKS/VPC."; \
		read -p "Continuar? [s/N] " confirm; \
		case "$$confirm" in [sS]|[sS][iI][mM]) ;; *) echo "Cancelado."; exit 1;; esac; \
	fi
	@echo "==> [1/2] Removendo Applications do ArgoCD (evita NLB/EBS órfãos)..."
	@KUBE_CONTEXT=$(EKS_CONTEXT) bash scripts/teardown-argocd-apps.sh 600
	@echo "==> [2/2] terraform destroy em $(EKS_DIR)..."
	cd $(EKS_DIR) && terraform destroy -auto-approve
	@echo "Cluster EKS destruído. Confira manualmente NLBs/EBS órfãos:"
	@echo "  aws elbv2 describe-load-balancers --region $(AWS_REGION) --query 'LoadBalancers[].LoadBalancerName'"
	@echo "  aws ec2 describe-volumes --region $(AWS_REGION) --filters Name=status,Values=available --query 'Volumes[].VolumeId'"

wait-eks:
	@KUBE_CONTEXT=$(EKS_CONTEXT) bash scripts/wait-argocd-healthy.sh

urls-eks:
	@echo "URLs das aplicações (LoadBalancer NLB):"
	@kubectl --context=$(EKS_CONTEXT) get svc -A --no-headers 2>/dev/null \
		| awk '$$3=="LoadBalancer"{print $$1, $$2, $$5, $$6}' \
		| while read -r ns svc host ports; do \
			port=$$(echo "$$ports" | cut -d: -f1 | cut -d, -f1); \
			printf "  %-15s http://%s:%s\n" "$$svc" "$$host" "$$port"; \
		done

argocd-password-eks:
	@kubectl --context=$(EKS_CONTEXT) get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d && echo

argocd-ui-eks:
	@echo "Abrindo port-forward para ArgoCD UI em https://localhost:8080"
	@echo "Usuário: admin"
	@echo "Senha: execute 'make argocd-password-eks' em outro terminal"
	@echo ""
	@echo "Pressione Ctrl+C para parar"
	kubectl --context=$(EKS_CONTEXT) port-forward svc/argocd-server -n argocd 8080:443
