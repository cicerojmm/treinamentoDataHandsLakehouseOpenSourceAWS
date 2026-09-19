# SPEC-011: CI/CD Genérico (GitHub Actions)

**Fase do projeto:** 2 — Camada de Código
**Pré-requisitos:** SPEC-002 (ECR)
**Bloqueia:** automação de deploy de SPEC-005, 008, 010, 012 (antes disso, builds são manuais)
**Status:** Specify

---

## 1. Contexto
Pipeline reutilizável de build/push/deploy para os 4 componentes de
código próprio (Airflow-DAGs, dbt, API, Spark jobs), usando GitHub
Actions (decisão fechada) e ECR com tags por Git SHA (decisão fechada).

## 2. Arquivos a criar
```
.github/workflows/
├── build-push-airflow-dags.yml
├── build-push-dbt.yml
├── build-push-api.yml
├── build-push-spark.yml
└── _reusable-build-push.yml      # workflow reutilizável, chamado pelos 4 acima
apps/local/argocd-image-updater-app.yaml   # se optar por Image Updater
```

## 3. Especificação técnica

### 3.1 Workflow reutilizável
`_reusable-build-push.yml` recebe como input: caminho do Dockerfile,
nome do repositório ECR, contexto de build. Executa:
1. Checkout do código
2. Login no ECR (`aws-actions/amazon-ecr-login`)
3. Build da imagem, tag = `${{ github.sha }}`
4. Push para o repositório ECR correspondente
5. Trigger de atualização do manifesto (ver 3.2)

### 3.2 Atualização do manifesto (deploy)
Definir no Plan entre duas abordagens:
- **ArgoCD Image Updater**: detecta automaticamente novas tags no ECR e
  atualiza a Application — menos código de pipeline, mas menos visível
  no Git (a atualização de tag não gera commit explícito por padrão,
  dependendo da estratégia de write-back configurada)
- **Commit automatizado**: o próprio workflow do GitHub Actions edita o
  `values.yaml`/CRD com a nova tag e faz commit direto na branch —
  mais explícito no histórico Git, mais alinhado ao princípio GitOps
  "tudo é um commit"

Recomendação a validar no Plan: **commit automatizado**, por manter
o histórico de deploys 100% rastreável no Git (preferível dado que o
projeto já valoriza rastreabilidade — tags por SHA, specs versionados).

### 3.3 Gatilho
Cada workflow dispara em push para `main` com mudanças no path
correspondente (`code/dbt-project/**`, `code/api-service/**`, etc.) —
evita rebuild de tudo a cada commit.

## 4. Ordem de execução esperada
```
1. Configurar Secrets do GitHub (credenciais AWS para ECR)
2. Criar o workflow reutilizável
3. Criar os 4 workflows específicos, cada um chamando o reutilizável
4. Testar com um commit trivial em cada um dos 4 componentes
```

## 5. Critério de Aceite
1. Push em `code/dbt-project/**` dispara apenas `build-push-dbt.yml`,
   não os outros 3
2. Imagem resultante aparece no ECR com tag = SHA do commit
3. O manifesto correspondente (`values.yaml` ou CRD) é atualizado
   automaticamente com a nova tag (via commit ou Image Updater,
   conforme decidido no Plan)
4. ArgoCD detecta a mudança e sincroniza sem intervenção manual
5. Pipeline falha corretamente (não publica imagem) se os testes do
   componente (`dbt test`, testes da API) falharem antes do build

## 6. Rollback / Recuperação
Reverter o commit de bump de tag no Git — ArgoCD sincroniza a versão
anterior automaticamente.

## 7. Fora de escopo
- Testes de integração completos em CI (rodar contra um cluster efêmero)
  — considerar como melhoria futura
- Deploy automático em EKS (isso só se aplica após SPEC-016/017)

## 8. Decisões pendentes (confirmar no Plan)
- Image Updater vs commit automatizado (ver 3.2) — decidir antes de implementar
