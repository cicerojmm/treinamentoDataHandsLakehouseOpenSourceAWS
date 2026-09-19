# SPEC-017: Overlays EKS (MinIO/EBS + ALB + External Secrets)

**Fase do projeto:** 4 — Migração para EKS
**Pré-requisitos:** SPEC-016 (cluster EKS existente), todos os specs locais (001-015) validados
**Bloqueia:** nenhum — spec final de migração
**Status:** Specify (incompleto — depende de decisões do SPEC-016 e de negócio)

---

## 1. Contexto
Adapta todos os componentes já validados localmente para rodar no EKS,
trocando apenas configuração declarativa (StorageClass, Ingress,
Secrets) — sem mudança de código, reforçando a paridade de ambientes
que é o objetivo central do projeto.

## 2. Arquivos a criar
```
apps/eks/                          # espelha apps/local/, com values-eks.yaml
charts/*/values-eks.yaml            # um por componente já existente
bootstrap/eks/
├── ebs-csi-driver-app.yaml
├── alb-controller-app.yaml
└── external-secrets-app.yaml
```

## 3. Especificação técnica (parcial)

### 3.1 Storage
Trocar `local-path` por `gp3` via EBS CSI Driver — usado por MinIO,
Hive Metastore Postgres, Airflow Postgres, Airbyte Postgres.

### 3.2 Ingress
AWS Load Balancer Controller (ALB) substitui `ingress-nginx` local.
TLS via ACM — domínio a definir.

### 3.3 Secrets
External Secrets Operator + AWS Secrets Manager substitui os Secrets
estáticos usados localmente (API key, credenciais de Postgres, MinIO
root credentials, etc.)

### 3.4 MinIO no EKS
MinIO Operator continua sendo usado (decisão fechada — sem migração
para S3 nativo), agora com storage `gp3` por trás e, possivelmente,
modo distribuído real (múltiplos nodes/drives) em vez de standalone.

### 3.5 ECR/IRSA
Pull de imagens passa a usar IRSA (SPEC-016) em vez do
`ecr-pull-secret` estático usado localmente (SPEC-002).

## 4. Critério de Aceite (parcial — completar após decisões)
1. Todos os componentes validados localmente (SPEC-001 a 015) sobem no
   EKS via os mesmos charts, apenas com `values-eks.yaml` diferente
2. Pipeline ponta a ponta (Airbyte → Airflow → dbt → API) roda no EKS
   com os mesmos critérios de aceite definidos em cada spec original
3. Acesso externo funciona via ALB + domínio real, com TLS válido
4. Nenhum Secret estático em texto puro no Git — tudo via External
   Secrets

## 5. Fora de escopo
- Qualquer mudança de lógica de negócio nos componentes de código
  próprio (dbt, API, Spark) — se precisar mudar código para funcionar
  no EKS, isso é um sinal de que algo foi mal desenhado antes

## 6. Decisões pendentes (bloqueantes — resolver antes do Plan)
- **Domínio** a ser usado para o ALB/ingress
- **Certificado TLS**: ACM gerenciado vs cert-manager
- **MinIO no EKS**: manter standalone (mais simples, menos resiliente)
  ou migrar para distributed mode (mínimo 4 drives/nodes)
- **Estratégia de backup**: dos Postgres dedicados e do MinIO, antes de
  considerar este ambiente como "produção" de fato
