# SPEC-001: Bootstrap do Cluster Local + ArgoCD + App of Apps

**Fase:** 0 — Bootstrap
**Pré-requisitos:** nenhum (ponto de partida do projeto)
**Bloqueia:** todos os specs seguintes (SPEC-002 em diante)

---

## 1. Contexto

Antes de qualquer componente da plataforma de dados existir, precisamos de:
1. Um cluster Kubernetes local reproduzível (`kind`)
2. ArgoCD instalado nesse cluster
3. Um mecanismo de "App of Apps" — uma única Application do ArgoCD que, ao ser aplicada, descobre e cria automaticamente todas as demais Applications do repositório

O objetivo deste spec é chegar a um estado onde **um único comando** sobe o cluster do zero e o ArgoCD já está de pé, pronto para sincronizar os componentes que serão adicionados nos specs seguintes (que ainda não existem neste momento — o app-of-apps vai apontar para um diretório `apps/local/` que começa vazio, exceto por um `.gitkeep` ou `README.md`).

Este spec **não** instala nenhum componente de dados (Airflow, MinIO etc.) — isso é escopo dos specs seguintes.

---

## 2. Pré-requisitos de ambiente

Ferramentas que precisam estar instaladas na máquina de desenvolvimento antes de começar:

| Ferramenta | Versão mínima | Verificação |
|---|---|---|
| Docker | 24.x | `docker version` |
| kind | 0.23.x | `kind version` |
| kubectl | 1.29.x | `kubectl version --client` |
| Helm | 3.14.x | `helm version` |
| git | qualquer recente | `git --version` |

Se alguma estiver faltando, informar antes de prosseguir — não assumir instalação automática dessas ferramentas de sistema.

---

## 3. Arquivos a criar

```
platform-repo/
├── infra/
│   └── clusters/
│       └── local/
│           └── kind-config.yaml
├── bootstrap/
│   ├── argocd/
│   │   ├── namespace.yaml
│   │   ├── install-values.yaml        # (se usar Helm chart do ArgoCD, não o manifest raw)
│   │   └── app-of-apps.yaml
│   └── namespaces.yaml
├── apps/
│   └── local/
│       └── README.md                  # placeholder, será populado nos próximos specs
├── Makefile
└── README.md                          # raiz do projeto, visão geral
```

---

## 4. Especificação técnica

### 4.1 `infra/clusters/local/kind-config.yaml`

Cluster com 1 control-plane + 2 workers, com mapeamento de portas para permitir acesso a ingress/serviços sem depender de LoadBalancer externo.

Requisitos:
- Nome do cluster: `data-platform-local`
- 1 nó `control-plane`, 2 nós `worker`
- `extraPortMappings` no control-plane mapeando `80` e `443` do host para o cluster (uso futuro do ingress-nginx)
- `extraPortMappings` adicional mapeando `8080` do host para a porta do ArgoCD UI (via NodePort ou como alternativa ao port-forward)

### 4.2 `bootstrap/namespaces.yaml`

Criar os namespaces que serão usados pelos specs seguintes, já antecipando a estrutura (evita ter que criar namespace a namespace depois):

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: argocd
---
apiVersion: v1
kind: Namespace
metadata:
  name: data-platform
---
apiVersion: v1
kind: Namespace
metadata:
  name: ingestion
---
apiVersion: v1
kind: Namespace
metadata:
  name: orchestration
---
apiVersion: v1
kind: Namespace
metadata:
  name: query-engine
---
apiVersion: v1
kind: Namespace
metadata:
  name: observability
---
apiVersion: v1
kind: Namespace
metadata:
  name: governance
```

### 4.3 Instalação do ArgoCD

Usar o **Helm chart oficial** (`argo/argo-cd`), não o manifest raw — facilita upgrades futuros e parametrização entre local/EKS.

Requisitos de `install-values.yaml`:
- `server.service.type: NodePort` (local) — no EKS isso será sobrescrito para usar ALB via overlay separado (fora do escopo deste spec)
- `configs.params."server.insecure": true` (só para ambiente local, simplifica acesso via HTTP sem cert — **não replicar isso no EKS**)
- Recursos limitados (requests/limits) compatíveis com ambiente local de 16GB RAM

Repo do chart: `https://argoproj.github.io/argo-helm`, chart `argo-cd`.

### 4.4 `bootstrap/argocd/app-of-apps.yaml`

Uma Application do ArgoCD que aponta para o próprio repositório, no path `apps/local/`, com `directory.recurse: true`. Todo arquivo `.yaml` dentro de `apps/local/` que for uma `Application` válida será automaticamente descoberto e sincronizado.

Campos obrigatórios:
- `metadata.name: app-of-apps`
- `spec.project: default`
- `spec.source.repoURL`: URL do repositório Git (placeholder a ser preenchido com o repo real do usuário)
- `spec.source.targetRevision: main`
- `spec.source.path: apps/local`
- `spec.destination.server: https://kubernetes.default.svc`
- `spec.syncPolicy.automated.prune: true`
- `spec.syncPolicy.automated.selfHeal: true`

> **Importante:** `selfHeal: true` significa que qualquer alteração manual feita depois no cluster (`kubectl edit`) será revertida automaticamente pelo ArgoCD. Isso é intencional — reforça a disciplina de só mudar via Git — mas avisar durante desenvolvimento, pois pode causar confusão ("mudei e voltou sozinho").

### 4.5 `Makefile`

Alvo único que orquestra todo o bootstrap, para permitir `make bootstrap-local` do zero:

Deve executar, em ordem:
1. Criar o cluster kind usando `kind-config.yaml` (se já não existir um cluster com esse nome)
2. Aplicar `bootstrap/namespaces.yaml`
3. Instalar ArgoCD via Helm no namespace `argocd`, usando `install-values.yaml`
4. Aguardar o ArgoCD server ficar `Ready` (`kubectl wait`)
5. Aplicar `bootstrap/argocd/app-of-apps.yaml`
6. Exibir instruções de acesso (comando de port-forward + como obter a senha inicial do admin)

Incluir também um alvo `make destroy-local` que deleta o cluster kind inteiro (`kind delete cluster --name data-platform-local`), para permitir recomeçar do zero facilmente durante o desenvolvimento.

---

## 5. Ordem de execução esperada

```bash
make bootstrap-local
```

Internamente, isso deve resultar em:
```
1. kind create cluster --config infra/clusters/local/kind-config.yaml
2. kubectl apply -f bootstrap/namespaces.yaml
3. helm repo add argo https://argoproj.github.io/argo-helm
4. helm install argocd argo/argo-cd -n argocd -f bootstrap/argocd/install-values.yaml
5. kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
6. kubectl apply -f bootstrap/argocd/app-of-apps.yaml
```

---

## 6. Critério de Aceite

O spec está concluído quando **todos** os itens abaixo forem verdadeiros:

1. `kind get clusters` lista `data-platform-local`
2. `kubectl get ns` mostra todos os namespaces definidos em `bootstrap/namespaces.yaml`
3. `kubectl get pods -n argocd` mostra todos os pods do ArgoCD em estado `Running`
4. `kubectl get application app-of-apps -n argocd` existe e está com `SYNC STATUS: Synced` e `HEALTH STATUS: Healthy`
5. Acesso à UI do ArgoCD funciona via:
   ```
   kubectl port-forward svc/argocd-server -n argocd 8080:443
   ```
   e login com usuário `admin` + senha obtida via:
   ```
   kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
   ```
6. `make destroy-local` seguido de `make bootstrap-local` reproduz o mesmo estado do zero, sem intervenção manual

---

## 7. Rollback / Recuperação

- Se o bootstrap falhar em qualquer etapa: `make destroy-local` e rodar novamente — o processo é idempotente e não depende de estado anterior.
- Se o ArgoCD subir mas o `app-of-apps` não sincronizar: verificar `spec.source.repoURL` no `app-of-apps.yaml` — causa mais comum é URL do repositório incorreta ou repositório ainda não público/acessível (para repos privados, será necessário configurar um `Secret` de credenciais do ArgoCD — **fora do escopo deste spec**, tratar como spec adicional se aplicável).

---

## 8. Fora de escopo (não fazer neste spec)

- Instalação de qualquer componente de dados (Airflow, MinIO, Trino etc.) — specs seguintes
- Configuração de ingress real (`ingress-nginx`) — apenas os `extraPortMappings` necessários para uso futuro
- TLS/certificados para o ArgoCD — ambiente local usa `insecure: true` propositalmente
- Qualquer configuração específica de EKS — este spec é exclusivamente para o ambiente local

---

## 9. Prompt sugerido para o Claude Code

```
Implemente o SPEC-001 conforme descrito neste arquivo. Crie a estrutura de
diretórios e arquivos exatamente como especificado na seção 3. Depois de
criar os arquivos, execute `make bootstrap-local` e valide cada item da
seção 6 (Critério de Aceite), reportando o resultado de cada verificação.
Se algum critério falhar, diagnostique a causa antes de propor correções.
```
