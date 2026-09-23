# SPEC-016: CI/CD (GitHub Actions → ECR → ArgoCD no EKS)

**Fase do projeto:** 5 — Automação de entrega
**Pré-requisitos:** SPEC-002 (ECR), SPEC-015 (overlays EKS)
**Bloqueia:** nenhum
**Status:** Specify (revisado 2026-09-23, aguardando aprovação)

---

## 1. Contexto
Hoje cada mudança em DAG, model dbt, API ou Metabase exige um deploy manual:
escolher a tag, fazer build e push da imagem, editar a tag no manifesto e
commitar, nessa ordem. Errar a ordem gera `ImagePullBackOff`. Esquecer um
dos dois lugares da tag do Airflow deixa as tasks numa versão diferente
do scheduler.

Este spec automatiza isso: o merge no `main` gera a imagem, publica no ECR
com tag = SHA curto do commit e atualiza o manifesto do EKS. O ArgoCD
sincroniza sozinho.

### Decisões fechadas
- **Fluxo Git:** mudança entra por PR e é mergeada no `main`. O CI roda
  no push em `main`, ou seja, depois do merge.
- **Atualização do manifesto:** commit automatizado do workflow direto no
  `main` (sem Image Updater). Permitido enquanto o `main` não for
  protegido. Quando for, o bot passa a abrir PR, e isso fica fora deste spec.
- **Acesso à AWS:** GitHub Secrets `AWS_ACCESS_KEY_ID` e
  `AWS_SECRET_ACCESS_KEY` de um usuário IAM dedicado, com permissão só
  de push nos repositórios ECR abaixo.
- **Imagens no escopo:** `airflow-dags`, `api-service`, `metabase`. As
  imagens `dbt-project` e `spark-jobs` saem do escopo (a `dbt-project` não
  é usada por nenhum componente; `spark-jobs` está vazio).
- **Ambiente:** o CI atualiza **só o EKS**. O ambiente local (`kind`)
  continua com deploy manual.
- **Tag:** SHA curto de 7 caracteres (`${GITHUB_SHA::7}`, ex.: `2af2674`).
  Nunca `latest`. As tags de timestamp atuais somem naturalmente no
  primeiro build de cada imagem pelo CI.
- **dbt dentro da imagem do Airflow (opção A):** o projeto dbt continua
  embutido na `airflow-dags`. O workflow do Airflow dispara por mudança em
  DAGs **ou** em models dbt.
- **Build da `airflow-dags` a partir da raiz do repo:** o Dockerfile
  passa a copiar `code/airflow-dags/dags` e `code/dbt-project` direto do
  contexto raiz, sem o passo de cópia do `build.sh`.
- **State do Terraform em backend S3 remoto:** hoje os states de
  `envs/shared` e `envs/eks` existem só na máquina local, sem trava e sem
  backup. Eles passam para um bucket S3 dedicado (versionado,
  criptografado, com acesso público bloqueado), usando a trava nativa do
  S3 (`use_lockfile = true`, sem DynamoDB). Isso **não** conflita com a
  decisão "MinIO em todos os ambientes", que trata do storage do
  lakehouse e não do state de infra.
- **Usuário IAM do CI no Terraform, access key fora dele:** o Terraform
  cria o usuário e a política. A access key é gerada manualmente
  (`aws iam create-access-key`) e vai direto para os GitHub Secrets.
  Nunca usar `aws_iam_access_key`, que grava a secret em texto puro no state.
- **Repositório ECR `metabase` sob o Terraform:** hoje ele existe fora do
  Terraform e sem política de ciclo de vida. Entra na lista
  `ecr_repositories` via `terraform import`, e com isso ganha a política
  padrão do módulo (mantém as últimas 20 imagens, o que basta para rollback).

## 2. Arquivos
```
.github/workflows/
├── _build-push-bump.yml          # reutilizável: testes → build → push ECR → bump do manifesto
├── airflow-dags.yml              # paths: code/airflow-dags/**, code/dbt-project/**
├── api-service.yml               # paths: code/api-service/** (exceto k8s-eks/)
└── metabase.yml                  # paths: code/metabase/**
code/airflow-dags/Dockerfile      # contexto = raiz do repo
code/airflow-dags/build.sh        # passa a só chamar docker build com contexto raiz (uso manual/bootstrap)
code/api-service/tests/           # pytest mínimo
code/api-service/requirements-dev.txt
infra/terraform/envs/shared/backend.tf     # backend S3
infra/terraform/envs/shared/iam-github.tf  # usuário IAM + política de push no ECR
infra/terraform/envs/shared/main.tf        # + "metabase" em ecr_repositories; required_version >= 1.10
infra/terraform/envs/eks/backend.tf        # backend S3
infra/terraform/envs/eks/providers.tf      # required_version >= 1.10
docs/runbooks/cicd-setup.md       # bucket de state, migração, access key, GitHub Secrets
```

Manifestos atualizados pelo bot (um por imagem):

| Imagem | Manifesto | Campo(s) |
|---|---|---|
| `airflow-dags` | `apps/eks/airflow-app.yaml` | `images.airflow.tag` **e** `config.kubernetes.worker_container_tag` |
| `api-service` | `code/api-service/k8s-eks/kustomization.yaml` | `image` do patch do Deployment |
| `metabase` | `charts/metabase-eks/metabase.yaml` | `image` do container |

## 3. Especificação técnica

### 3.1 Workflow reutilizável `_build-push-bump.yml`
Entradas: nome da imagem (repo ECR `data-platform/<nome>`), Dockerfile,
contexto de build, comando de teste (opcional) e manifesto e regra de
substituição da tag.

Passos:
1. Checkout.
2. **Testes do componente** (3.3). Se falharem, o workflow para **antes** do build.
3. Login no ECR (`aws-actions/configure-aws-credentials` com os secrets
   + `aws-actions/amazon-ecr-login`), região `us-east-2`.
4. Build com cache de camadas (`docker/build-push-action` com cache do
   GitHub Actions) e push da tag `${GITHUB_SHA::7}`.
5. Confirmar que a imagem existe no ECR antes do bump.
6. Bump do manifesto: substituir a tag, commitar como
   `deploy(<imagem>): <sha7>` e fazer push no `main`, com
   `git pull --rebase` e retry, porque workflows paralelos podem
   commitar ao mesmo tempo.
7. `concurrency` por imagem, para dois merges seguidos não publicarem
   fora de ordem (o mais recente vence).

Commits feitos com `GITHUB_TOKEN` não disparam novos workflows (regra do
GitHub), então o bump não gera loop. Mesmo assim, os filtros de path
excluem os manifestos, por clareza.

### 3.2 Gatilhos
- `airflow-dags.yml`: push em `main` com mudança em `code/airflow-dags/**`
  ou `code/dbt-project/**`.
- `api-service.yml`: `code/api-service/**`, exceto `code/api-service/k8s-eks/**`.
- `metabase.yml`: `code/metabase/**`.
- Todos aceitam `workflow_dispatch` para rebuild manual.

### 3.3 Testes (portão antes do build)
- **dbt (sem banco):** `dbt deps` + `dbt parse` com o profile do projeto.
  Valida Jinja, `ref`/`source`, YAML e a definição dos testes, sem
  conectar no Trino.
- **DAGs:** dentro da imagem recém-buildada (antes do push), carregar a
  pasta de DAGs com `DagBag` e exigir zero erros de import.
- **API (pytest mínimo, sem MinIO):**
  - conversão de `NULL`/`NaN` em `null` no JSON (regressão do bug de
    2026-09-23 em `/api/v1/movies`);
  - request sem `X-API-Key` ou com chave errada devolve 401;
  - endpoint `/health` responde 200.
- **Metabase:** só o build (imagem base + driver, sem código próprio).

### 3.4 Usuário IAM e secrets
Usuário IAM dedicado (`github-actions-ecr`), criado pelo Terraform em
`envs/shared`, com política mínima: `ecr:GetAuthorizationToken` e as
ações de push (`BatchCheckLayerAvailability`, `InitiateLayerUpload`,
`UploadLayerPart`, `CompleteLayerUpload`, `PutImage`, `BatchGetImage`,
`DescribeImages`) restritas aos 3 repositórios
`data-platform/{airflow-dags,api-service,metabase}`. A access key é criada
fora do Terraform e vai direto para os GitHub Secrets. Passo a passo em
`docs/runbooks/cicd-setup.md`.

### 3.5 State do Terraform (backend S3)
1. O bucket de state é criado **uma vez**, via CLI, documentado no
   runbook: o Terraform não guarda o próprio state no bucket que ele
   mesmo cria. Regras do bucket: versionamento ligado, SSE-S3, bloqueio de
   acesso público, região `us-east-2`.
2. `backend "s3"` em `envs/shared` e `envs/eks` (keys separadas por
   ambiente), com `use_lockfile = true` e `encrypt = true`.
3. Migração: `terraform init -migrate-state` em cada ambiente. Depois
   de validar, apagar os `terraform.tfstate*` locais.
4. `required_version = ">= 1.10"` (exigido pela trava nativa do S3; a
   versão local é 1.14.1).
5. Ordem: migrar os states **antes** de criar o usuário IAM e importar o
   ECR `metabase`.

Por mexer em backend e IAM, a implementação desta seção segue Plan Mode
(regra do `CLAUDE.md` para infra sensível).

## 4. Critério de Aceite
1. Push em `code/dbt-project/**` dispara **só** `airflow-dags.yml`.
   Push em `code/api-service/app/**` dispara só `api-service.yml`.
   Push em `code/metabase/**` dispara só `metabase.yml`
   (`gh run list` / aba Actions).
2. A imagem aparece no ECR com tag igual ao SHA curto do commit do merge:
   `aws ecr describe-images --repository-name data-platform/<img> --image-ids imageTag=<sha7>`.
3. O manifesto correspondente recebe commit do bot com a nova tag. No
   Airflow, **os dois campos** mudam juntos:
   `git log -1 -- apps/eks/airflow-app.yaml` e `grep <sha7>` mostram 2 ocorrências.
4. O ArgoCD sincroniza sem intervenção e o pod roda a imagem nova:
   `kubectl get deploy <x> -o jsonpath='{..image}'` contém `<sha7>`.
5. Com um teste quebrado (model dbt com `ref` inválido, DAG com erro de
   import ou teste da API falhando), o workflow falha e **nenhuma imagem é
   publicada** nem manifesto alterado.
6. Nenhum manifesto do EKS referencia `latest`:
   `grep -rn ":latest\|tag: latest" apps/eks charts/*-eks code/*/k8s-eks` vazio.
7. Os states do Terraform estão no S3 e não há state local:
   `terraform state list` funciona num checkout limpo (em `envs/shared` e
   `envs/eks`), e `find infra/terraform -name '*.tfstate'` volta vazio.
8. Nenhuma credencial no state: `terraform state list | grep aws_iam_access_key` vazio.
9. `terraform plan` em `envs/shared` sem mudanças pendentes, com o
   `metabase` gerenciado e com lifecycle policy:
   `aws ecr get-lifecycle-policy --repository-name data-platform/metabase` responde.

## 5. Fora de escopo
- Ambiente local (`kind`): manifestos e deploy continuam manuais.
- Proteção de branch no `main` e bump via PR (próxima fase).
- `dbt test`/`dbt build` contra o Trino (precisa de ambiente efêmero).
- Imagens `dbt-project` e `spark-jobs`. A remoção dos repositórios ECR e
  do `code/dbt-project/Dockerfile` fica para um passo separado.
- ArgoCD Image Updater, role OIDC e credenciais temporárias.

## 6. Rollback / Recuperação
- Reverter o commit de bump (`deploy(<imagem>): <sha7>`) no Git. O
  ArgoCD volta a imagem anterior, que continua no ECR.
- Desligar o CI: desabilitar os workflows na aba Actions. O deploy
  manual (`make images-eks` + edição da tag) continua funcionando.

## 7. Decisões para o Plan
- Como o `dbt parse` obtém o profile no CI (target dedicado no
  `profiles.yml` ou variáveis de ambiente) sem conexão real.
- Nome do bucket de state. Sugestão: `data-platform-tfstate-093499160510`,
  com o ID da conta para garantir unicidade global.
