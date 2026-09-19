# SPEC-014: OpenMetadata + Ingestion Connectors

**Fase do projeto:** 3 — Observabilidade e Governança
**Pré-requisitos:** SPEC-005 (Airflow), SPEC-007 (Trino), SPEC-008 (dbt)
**Bloqueia:** nenhum spec técnico direto
**Status:** Specify

---

## 1. Contexto
Catálogo de dados e linhagem. Componente mais pesado de rodar
localmente (exige Elasticsearch/OpenSearch + banco relacional próprio) —
avaliar no Plan se roda em perfil "full" apenas, não no perfil "core"
do dia a dia de desenvolvimento.

## 2. Arquivos a criar
```
charts/openmetadata/
└── values-local.yaml
apps/local/openmetadata-app.yaml
docs/runbooks/openmetadata-connectors-setup.md
```

## 3. Especificação técnica

### 3.1 Dependências
- OpenSearch (ou Elasticsearch) dedicado
- Postgres ou MySQL dedicado (backend do próprio OpenMetadata) —
  manter a mesma lógica de "Postgres dedicado por componente"

### 3.2 Ingestion Connectors
Configurar, via UI ou API do OpenMetadata:
- **Trino**: metadata de schemas/tabelas do catálogo Iceberg
- **Airflow**: pipelines e execuções (linhagem de orquestração)
- **dbt**: modelos, testes e linhagem de transformação (usando o
  `manifest.json` gerado pelo `dbt build`)

## 4. Ordem de execução esperada
```
1. ArgoCD sincroniza openmetadata-app (com suas dependências)
2. Configurar os 3 connectors via UI (documentado no runbook)
3. Rodar ingestion inicial
```

## 5. Critério de Aceite
1. `kubectl get pods -n governance` mostra todos os pods em `Running`
2. UI do OpenMetadata acessível via port-forward
3. Os 3 connectors (Trino, Airflow, dbt) configurados e com ingestion
   bem-sucedida (sem erro na última execução)
4. Uma tabela de mart (criada no SPEC-008) aparece no catálogo com
   linhagem completa: fonte Postgres → Airbyte → staging → mart

## 6. Rollback / Recuperação
Reingestão completa resolve a maioria dos problemas de sincronização;
estado crítico está no Postgres/OpenSearch dedicados.

## 7. Fora de escopo
- Customização de políticas de governança/classificação de dados
  sensíveis — considerar spec futuro se necessário
- Alta disponibilidade do OpenSearch — não necessário na Fase 1-3

## 8. Decisões pendentes (confirmar no Plan)
- Rodar OpenMetadata sempre junto do "core" local ou só sob demanda
  (perfil "full"), dado o custo de recursos — recomendo perfil "full"
  para não pesar o dia a dia de desenvolvimento dos demais componentes
