# Runbook: CI/CD (GitHub Actions → ECR → ArgoCD)

Configuração manual necessária uma única vez (por repositório GitHub).
Refazer se o repositório for recriado.

## 1. Configurar os Secrets do GitHub

**Decisão deste spec:** usa as credenciais já configuradas localmente
(conta root da AWS, `093499160510`) — sem usuário IAM dedicado por
enquanto. **Risco aceito:** essas credenciais têm acesso total à conta,
não só ao ECR. Se um dia migrar para um usuário IAM com permissão
mínima, essa é a única seção que muda.

1. Pegue as chaves da sua credencial local (nunca cole a chave num
   comando que fique salvo em histórico de shell compartilhado):
   ```bash
   aws configure get aws_access_key_id
   aws configure get aws_secret_access_key
   ```
2. No GitHub: **Settings → Secrets and variables → Actions → New
   repository secret**. Criar dois secrets:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`

   Alternativa via `gh` CLI (se instalado):
   ```bash
   aws configure get aws_access_key_id | gh secret set AWS_ACCESS_KEY_ID
   aws configure get aws_secret_access_key | gh secret set AWS_SECRET_ACCESS_KEY
   ```

## 2. Como os workflows funcionam

Cada componente (`airflow-dags`, `api-service`, `metabase`) tem seu
próprio workflow em `.github/workflows/`, todos chamando o reutilizável
`_build-push-bump.yml`. Fluxo, no push em `main` que toca no path do
componente:

1. Testes do componente (antes de publicar qualquer coisa).
2. Build da imagem, tag = SHA curto do commit (`${GITHUB_SHA::7}`).
3. Push pro ECR.
4. Commit automático (`github-actions[bot]`) atualizando a tag no
   manifesto do EKS correspondente, direto no `main`.
5. O ArgoCD detecta o commit e sincroniza sozinho.

Esse commit automático **não** dispara um novo workflow (regra do
GitHub: eventos gerados pelo `GITHUB_TOKEN` não retriggeram Actions),
então não há loop.

## 3. Testar um workflow manualmente

Todos os 3 workflows aceitam `workflow_dispatch`, então dá pra rodar sem
esperar um push real:

```bash
gh workflow run airflow-dags.yml
gh workflow run api-service.yml
gh workflow run metabase.yml
gh run watch
```

Ou pela aba **Actions** do GitHub, botão "Run workflow".

## 4. Rollback

Se uma imagem publicada quebrar algo em produção:

```bash
git revert <commit-de-bump>   # ex.: "deploy(api-service): abc1234"
git push origin main
```

O ArgoCD sincroniza a tag anterior automaticamente — a imagem antiga
continua no ECR (nada é apagado, a política de lifecycle só remove
depois de acumular mais de 20 imagens).

Para desligar o CI por completo (sem reverter nada): aba **Actions** →
selecionar o workflow → **Disable workflow**. O deploy manual
(`make images-eks`) continua funcionando normalmente.

## 5. Uso manual continua funcionando

Nada neste spec muda o fluxo manual — só adiciona a automação por cima:

```bash
make images-eks      # builda/publica só o que faltar no ECR
make bootstrap-eks    # cluster do zero, chama images-eks internamente
```

`scripts/ensure-images-eks.sh` lê a tag direto dos manifestos, então
funciona igual não importa se a tag ali foi colocada manualmente ou por
um workflow do CI.
