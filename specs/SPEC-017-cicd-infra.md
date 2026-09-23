# SPEC-017: CI/CD de Infraestrutura (Terraform + Bootstrap via GitHub Actions)

**Fase do projeto:** 5 — Automação de entrega
**Pré-requisitos:** SPEC-016 (CI/CD de imagens), SPEC-014 (Terraform EKS)
**Bloqueia:** nenhum
**Status:** Specify (decisões fechadas 2026-09-23, aguardando aprovação)

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

### Princípio de reuso
O workflow **não reimplementa** a lógica do bootstrap em YAML — ele
chama `make bootstrap-eks CONFIRM=yes` de dentro do runner (com
terraform/kubectl/helm/aws instalados). Fonte única de verdade continua
sendo o Makefile; o CI só troca "quem aperta o botão".

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
.github/workflows/infra-bootstrap.yml   # workflow_dispatch, roda make bootstrap-eks
docs/runbooks/cicd-setup.md             # + seção sobre este workflow
```

## 4. Critério de Aceite (rascunho)
1. `workflow_dispatch` do `infra-bootstrap.yml` roda `make bootstrap-eks CONFIRM=yes`
   dentro do runner e termina com sucesso (mesmo critério de saída que o
   Makefile já usa: todas as Applications Synced/Healthy + buckets do MinIO
   verificados).
2. Depois do workflow terminar, `kubectl get applications -n argocd`
   mostra todas Synced/Healthy — sem nenhum passo manual extra.
3. **Prova de ponta a ponta:** com o ambiente já de pé, um push em
   `code/api-service/**` dispara o workflow do SPEC-016, que builda,
   publica e faz bump do manifesto; sem nenhuma ação manual, o ArgoCD
   sincroniza e `kubectl get deploy lakehouse-api -o jsonpath='{..image}'`
   passa a mostrar a tag nova, dentro de alguns minutos.
4. Rodar o workflow duas vezes seguidas (cluster já existente) é
   idempotente — `terraform plan` não mostra recriação de recursos.

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

