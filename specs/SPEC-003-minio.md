# SPEC-003: MinIO Operator + Buckets do Lakehouse

**Fase do projeto:** 1 — Core de Infraestrutura
**Pré-requisitos:** SPEC-001
**Bloqueia:** SPEC-004 (Hive Metastore), SPEC-006 (Airbyte), SPEC-007 (Trino), SPEC-012 (Spark)
**Status:** Specify

---

## 1. Contexto
MinIO é o object storage do lakehouse, usado em todos os ambientes
(decisão fechada — sem migração para S3 nativo). Este spec sobe o MinIO
Operator e cria a estrutura de buckets que sustenta todo o fluxo
raw → staged → curated.

## 2. Arquivos a criar
```
charts/minio/
├── values-local.yaml
└── values-eks.yaml              # placeholder, detalhado no SPEC-017
apps/local/minio-operator-app.yaml
apps/local/minio-tenant-app.yaml
bootstrap/minio/
└── create-buckets-job.yaml       # Job Kubernetes que cria os buckets
```

## 3. Especificação técnica

### 3.1 MinIO Operator
Instalar via chart oficial `minio/operator` no namespace `data-platform`.

### 3.2 Tenant MinIO
Um `Tenant` (CRD do MinIO Operator) com:
- Modo local: **standalone** (1 pool, sem erasure coding distribuído —
  4+ drives não fazem sentido num único node de desenvolvimento)
- Modo EKS (detalhar no SPEC-017): distributed, storage via EBS
- Credenciais root geradas via Secret, referenciadas pelo Tenant

### 3.3 Buckets (Padrão Medallion)
Criados via `Job` pós-instalação usando `mc` (MinIO client):
- `bronze` — dados brutos recém-ingeridos (raw)
- `silver` — dados limpos e transformados (staging)
- `gold` — dados prontos para consumo (dbt marts, tabelas Iceberg)

Políticas de bucket: por ora, acesso liberado apenas às credenciais da
aplicação (Trino, Spark, Airbyte, API) — sem acesso público.

## 4. Ordem de execução esperada
```
1. ArgoCD sincroniza minio-operator-app (instala o Operator)
2. ArgoCD sincroniza minio-tenant-app (cria o Tenant)
3. create-buckets-job roda automaticamente após o Tenant ficar Ready
   (usar Argo CD sync wave ou Job com initContainer aguardando o serviço)
```

## 5. Critério de Aceite
1. `kubectl get tenant -n data-platform` mostra status `Initialized`
2. `kubectl get pods -n data-platform` mostra os pods do MinIO em `Running`
3. Rodando `mc ls minio-local/` (via port-forward + mc client) lista os
   3 buckets: `bronze`, `silver`, `gold`
4. Upload de teste: `mc cp arquivo.txt minio-local/bronze/` funciona e o
   arquivo aparece no console web do MinIO

## 6. Rollback / Recuperação
Deletar o `Tenant` (`kubectl delete tenant`) recria o storage do zero —
aceitável em ambiente local. Nunca fazer isso no EKS sem backup.

## 7. Fora de escopo
- Configuração de erasure coding distribuído (só relevante no EKS)
- Políticas de lifecycle dos buckets (retenção, versionamento) — avaliar
  se necessário ao chegar no SPEC-017

## 8. Decisões assumidas
- Tamanho do volume local: assumindo 20Gi para o pool standalone — ajustar
  conforme volume de dados de teste real
- Nome do tenant/serviço: `minio-local` (usado como referência de endpoint
  pelos specs seguintes — Hive Metastore, Trino, Spark, API)
