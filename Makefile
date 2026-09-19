.PHONY: bootstrap-local destroy-local argocd-password argocd-ui

CLUSTER_NAME := data-platform-local
KIND_CONFIG := infra/clusters/local/kind-config.yaml

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
		helm upgrade argocd argo/argo-cd -n argocd -f bootstrap/argocd/install-values.yaml --wait; \
	else \
		helm install argocd argo/argo-cd -n argocd -f bootstrap/argocd/install-values.yaml --wait; \
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
