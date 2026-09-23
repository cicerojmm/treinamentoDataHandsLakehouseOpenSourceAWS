# SPEC-017: CI/CD de Infraestrutura (Terraform + Bootstrap via GitHub Actions)

**Fase do projeto:** 5 — Automação de entrega
**Pré-requisitos:** SPEC-016 (CI/CD de imagens), SPEC-014 (Terraform EKS)
**Bloqueia:** nenhum
**Status:** Plan aprovado (2026-09-23), aguardando Implement

---

## 1. Contexto
O SPEC-016 automatizou build/push/deploy das 3 imagens de aplicação
(`airflow-dags`, `api-service`, `metabase`), mas deixou de propósito
fora de escopo a infraestrutura em si: hoje `make bootstrap-eks` (que
roda `terraform apply` do cluster, instala o ArgoCD e aplica o
app-of-apps) só roda manualmente, na máquina do usuário.

Este spec estende o CI/CD para também rodar essa parte, via
`workflow_dispatch`: um clique cria o cluster do zero (ou atualiza um
existente), garante as imagens no ECR, sobe o ArgoCD e aplica o
app-of-apps — os mesmos 7 passos que `make bootstrap-eks` já faz hoje,
só que disparados pelo GitHub Actions em vez de rodados localmente.

**Não é escopo construir nada novo para "o ArgoCD atualizar quando uma
imagem muda"** — isso já funciona hoje: toda Application tem
`syncPolicy.automated`, e o commit de bump do SPEC-016 já é suficiente
para o ArgoCD detectar e sincronizar sozinho (validado várias vezes
nesta sessão). O que este spec adiciona aqui é um **critério de aceite
que prova isso de ponta a ponta via CI** (build → push → bump → pod
rodando a imagem nova, sem intervenção manual), não uma nova lógica de
sincronização.

### Decisões fechadas (herdadas do SPEC-016, sem reabrir)
- Credenciais: mesmos GitHub Secrets `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`
  (conta root) — sem usuário IAM dedicado por enquanto.
- Backend do Terraform: mesmo bucket S3 (`cjmm-datahandson-configs`),
  já configurado nos dois ambientes.

### Princípio de reuso: 3 jobs visíveis, não um `make bootstrap-eks` opaco
Requisito do usuário: o workflow precisa deixar visível, como estágios
separados na UI do GitHub Actions, a sequência **Terraform → imagens →
deploy/ArgoCD** — não esconder tudo atrás de um único comando.

Hoje `bootstrap-eks` é um alvo monolítico do Makefile (terraform apply +
kubeconfig + imagens + ArgoCD + app-of-apps + wait + verify, tudo numa
tacada). Este spec quebra ele em 3 sub-alvos reutilizáveis, e
`bootstrap-eks` passa a **chamar os 3 em sequência** — uso manual
idêntico ao de hoje, sem mudança de comportamento:

- `terraform-apply-eks` — terraform apply + `aws eks update-kubeconfig`
- `images-eks` — já existe, sem mudança
- `deploy-argocd-eks` — helm install/upgrade ArgoCD + apply do
  app-of-apps + `wait-argocd-healthy.sh` + `verify-minio-buckets.sh`

O workflow `infra-bootstrap.yml` tem 3 jobs encadeados (`needs:`), cada
um chamando um desses sub-alvos:
```
job terraform      -> make terraform-apply-eks
job build-images    (needs: terraform)    -> make images-eks
job deploy           (needs: build-images) -> make deploy-argocd-eks
```
Fonte única de verdade continua sendo o Makefile — o workflow só chama
os mesmos 3 sub-alvos que o uso manual (`make bootstrap-eks`) também
chama por baixo.

**Nota técnica:** cada job do GitHub Actions roda numa VM efêmera
separada — o `kubeconfig` gerado no job `terraform` não existe mais no
job `deploy` (rodam em runners diferentes, sem filesystem
compartilhado). Por isso `deploy-argocd-eks` roda `aws eks
update-kubeconfig` de novo no começo, em vez de depender de um artefato
do job anterior — é barato (só lê metadado do cluster na API da AWS) e
idempotente, e já é assim que o Makefile funciona hoje pra uso manual
(rodar `deploy-argocd-eks` sozinho, sem ter acabado de rodar
`terraform-apply-eks` na mesma sessão de shell, também precisa
funcionar).

## 2. Decisões fechadas nesta revisão (2026-09-23)
- **Sem gate de aprovação:** `workflow_dispatch` roda o `terraform apply`
  direto, sem `GitHub Environment`/required reviewer no meio. Quem tem
  push no repo pode disparar o bootstrap completo sozinho. Risco aceito
  pelo usuário (mesmo espírito da decisão de credenciais root do
  SPEC-016 — infra de ambiente de testes, não produção real).
- **`terraform destroy` fica fora deste spec**, continua manual/local
  via `make destroy-eks`. Destruir por engano via CI é mais perigoso do
  que criar por engano, e não há necessidade prática de automatizar
  algo que já é rápido e intencional rodando localmente.

## 3. Arquivos (esboço, sujeito ao Plan)
```
Makefile                                # bootstrap-eks quebrado em 3 sub-alvos
                                         #   terraform-apply-eks (novo)
                                         #   images-eks (existente, sem mudança)
                                         #   deploy-argocd-eks (novo)
                                         # bootstrap-eks passa a chamar os 3 em sequência
.github/workflows/infra-bootstrap.yml   # workflow_dispatch, 3 jobs encadeados (needs:)
docs/runbooks/cicd-setup.md             # + seção sobre este workflow
```

## 4. Critério de Aceite (rascunho)
1. `make bootstrap-eks CONFIRM=yes` continua funcionando manualmente,
   do jeito que já funciona hoje, chamando os 3 sub-alvos novos por
   dentro (sem mudança de comportamento observável).
2. `workflow_dispatch` do `infra-bootstrap.yml` mostra **3 jobs
   separados** na UI do Actions (`terraform`, `build-images`, `deploy`),
   cada um com seu próprio resultado, na ordem `terraform → build-images
   → deploy` (`needs:` entre eles).
3. Ao final dos 3 jobs, `kubectl get applications -n argocd` mostra
   todas Synced/Healthy — sem nenhum passo manual extra.
4. **Prova de ponta a ponta:** com o ambiente já de pé, um push em
   `code/api-service/**` dispara o workflow do SPEC-016, que builda,
   publica e faz bump do manifesto; sem nenhuma ação manual, o ArgoCD
   sincroniza e `kubectl get deploy lakehouse-api -o jsonpath='{..image}'`
   passa a mostrar a tag nova, dentro de alguns minutos.
5. Rodar o workflow duas vezes seguidas (cluster já existente) é
   idempotente — `terraform plan` não mostra recriação de recursos, e o
   job `build-images` não rebuilda o que já existe no ECR (mesmo
   comportamento do `ensure-images-eks.sh` hoje).

## 5. Fora de escopo
- Automatizar o `terraform destroy` via CI — decisão fechada, fica
  manual/local (seção 2).
- Usuário IAM dedicado (herdado do SPEC-016).
- Gate de aprovação antes do `apply` — decisão fechada, sem gate
  (seção 2).

## 6. Rollback / Recuperação
Igual ao manual hoje: `make destroy-eks` localmente. O workflow não
adiciona nenhum estado novo além do que o Terraform já gerencia (state
no S3, compartilhado com o uso manual).

