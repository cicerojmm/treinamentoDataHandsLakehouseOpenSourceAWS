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
apps/eks/openmetadata-dependencies-app.yaml   # Airflow gerenciado, dedicado ao OpenMetadata
charts/postgres-eks/openmetadata-airflow-postgres.yaml
docs/runbooks/openmetadata-connectors-setup.md
```

## 3. Especificação técnica

### 3.1 Dependências
- OpenSearch (ou Elasticsearch) dedicado
- Postgres ou MySQL dedicado (backend do próprio OpenMetadata) —
  manter a mesma lógica de "Postgres dedicado por componente"
- **Airflow gerenciado (Managed Airflow), dedicado ao OpenMetadata** —
  ver 3.3. Diferente do Airflow principal da plataforma (SPEC-005/009);
  existe só para o OpenMetadata deployar/rodar Ingestion Pipelines pela
  própria UI dele.

### 3.2 Ingestion Connectors
Configurar, via UI ou API do OpenMetadata:
- **Trino**: metadata de schemas/tabelas do catálogo Iceberg
- **Airflow**: pipelines e execuções do Airflow *principal* da
  plataforma (namespace `ingestion`) — harvesting read-only de metadata,
  não depende do Managed Airflow do OpenMetadata
- **dbt**: modelos, testes e linhagem de transformação (usando o
  `manifest.json` gerado pelo `dbt build`)

Rodar (deployar/"Run Now") qualquer uma dessas Ingestion Pipelines pela
UI do OpenMetadata **depende** do Managed Airflow (3.3) — é o
executor por trás do botão Deploy/Run Now, independente de qual
connector está sendo ingerido.

### 3.3 Managed Airflow do OpenMetadata
O OpenMetadata usa `pipelineServiceClientConfig` (chart `openmetadata`,
já configurado) apontando por padrão para
`http://openmetadata-dependencies-web:8080` — precisa de um Airflow
com o plugin `openmetadata-managed-apis` já instalado, servido nesse
endereço.

- **Chart:** `open-metadata/openmetadata-dependencies` (mesma versão
  do chart `openmetadata`, hoje `1.5.4`), com `mysql.enabled: false` e
  `opensearch.enabled: false` (reaproveita o Postgres e o OpenSearch
  dedicados já existentes, em vez de subir instâncias novas)
- **Imagem:** `docker.getcollate.io/openmetadata/ingestion:1.5.4` —
  build oficial do OpenMetadata, já com o plugin instalado (não precisa
  de imagem customizada própria)
- **Nome do release Helm:** precisa ser exatamente
  `openmetadata-dependencies` — o Service resultante
  (`openmetadata-dependencies-web:8080`) bate com o `apiEndpoint`
  padrão do chart `openmetadata`, sem precisar sobrescrever nada
- **Banco:** `airflow.externalDatabase.type: postgres`, apontando para
  um Postgres dedicado novo (`openmetadata-airflow-postgres`, mesmo
  padrão dos demais componentes) — chart suporta `mysql` ou `postgres`
  nativamente, evita introduzir um motor de banco novo no projeto
- **Credenciais:** usuário admin do Airflow (`airflow.airflow.users`)
  precisa da mesma senha já configurada no secret
  `airflow-secrets`/`openmetadata-airflow-creds` (usado pelo
  `pipelineServiceClientConfig.auth.password`) — manter os dois em
  sincronia
- **Executor:** `KubernetesExecutor` (sem worker/flower/redis)

## 4. Ordem de execução esperada
```
1. ArgoCD sincroniza openmetadata-dependencies-app (Managed Airflow)
2. ArgoCD sincroniza openmetadata-app (servidor principal)
3. Configurar os 3 connectors via UI (documentado no runbook)
4. Rodar ingestion inicial (Deploy/Run Now, via Managed Airflow)
```

## 5. Critério de Aceite
1. `kubectl get pods -n governance` mostra todos os pods em `Running`
2. UI do OpenMetadata acessível
3. Settings → Pipeline Services não mostra erro de conexão com o
   Managed Airflow (`ConnectException` em `openmetadata-dependencies-web`)
4. Os 3 connectors (Trino, Airflow, dbt) configurados e com ingestion
   bem-sucedida (sem erro na última execução), disparada pela própria
   UI (Deploy/Run Now)
5. Uma tabela de mart (criada no SPEC-008) aparece no catálogo com
   linhagem completa: fonte Postgres → Airbyte → staging → mart

## 6. Rollback / Recuperação
Reingestão completa resolve a maioria dos problemas de sincronização;
estado crítico está no Postgres/OpenSearch dedicados (incluindo o
Postgres do Managed Airflow).

## 7. Fora de escopo
- Customização de políticas de governança/classificação de dados
  sensíveis — considerar spec futuro se necessário
- Alta disponibilidade do OpenSearch — não necessário na Fase 1-3
- Ingestion pipelines via CLI (`metadata ingest`), sem depender do
  Managed Airflow — alternativa possível, não adotada aqui

## 8. Decisões pendentes (confirmar no Plan)
- Rodar OpenMetadata sempre junto do "core" local ou só sob demanda
  (perfil "full"), dado o custo de recursos — recomendo perfil "full"
  para não pesar o dia a dia de desenvolvimento dos demais componentes
- ~~Managed Airflow dedicado~~ — decidido: subir via
  `openmetadata-dependencies` (3.3), reaproveitando Postgres/OpenSearch
  dedicados em vez de MySQL/OpenSearch embutidos no chart
