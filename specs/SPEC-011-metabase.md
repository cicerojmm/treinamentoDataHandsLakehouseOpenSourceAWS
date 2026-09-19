# SPEC-011: Metabase (BI conectado ao Trino)

**Fase do projeto:** 2 — Camada de Código
**Pré-requisitos:** SPEC-007 (Trino)
**Bloqueia:** nenhum
**Status:** Implementado

---

## 1. Contexto

Ferramenta de BI para visualização dos dados do lakehouse. Conecta direto no Trino para consultar as tabelas Iceberg (bronze/silver/gold).

## 2. Arquivos criados

```
charts/metabase/
├── kustomization.yaml
├── postgres.yaml
├── metabase.yaml
apps/local/metabase-app.yaml
docs/runbooks/metabase-trino-setup.md
```

## 3. Especificação técnica

### 3.1 Metabase
- Imagem oficial `metabase/metabase`
- PostgreSQL dedicado como backend (metadados do Metabase)
- Conexão com Trino via driver Starburst/Trino

### 3.2 Conexão Trino
- Host: `trino.query-engine.svc.cluster.local`
- Port: `8080`
- Catalog: `iceberg`
- Schema: `default` (ou gold)

## 4. Critério de Aceite

1. Metabase acessível via port-forward
2. Conexão com Trino configurada e funcionando
3. Query em tabela gold executada com sucesso no Metabase
4. Dashboard de exemplo criado com dados do Movielens

## 5. Rollback

Deletar Application do ArgoCD remove Metabase sem afetar dados do lakehouse.
