# Plataforma de Dados OpenSource

## Contexto do projeto
Plataforma de dados em Kubernetes (local `kind` → EKS), GitOps via ArgoCD.

Fluxo de dados:
```
Airbyte → s3://bronze (Parquet raw)
            ↓
Airflow → Trino (hive_bronze) → dbt → s3://warehouse (Iceberg)
            │                           ├── staging/ (views)
            │                           ├── silver/  (tabelas)
            │                           └── gold/    (tabelas)
            ↓
        API (DuckDB) ← lê gold
            ↓
        Metabase ← conecta via Trino

Grafana + OpenMetadata (observabilidade/governança, transversal)
```

Arquitetura do Lakehouse:
- **bronze/** (bucket): Parquet raw do Airbyte, lido via catálogo `hive_bronze` no Trino
- **warehouse/** (bucket): Tabelas Iceberg (staging/silver/gold), gerenciadas via catálogo `iceberg` no Trino
- **DAG dbt_movielens**: Cria external tables no hive_bronze e executa dbt (staging → silver → gold)

## Decisões de arquitetura fechadas (não reabrir sem justificativa nova)
- **Catálogo do Iceberg (Trino):** JDBC Catalog com PostgreSQL dedicado (tabelas `iceberg_tables`, `iceberg_namespace_properties`) — Hive Metastore não compatível com filesystem nativo S3 do Trino 480+
- **Storage do lakehouse:** MinIO em todos os ambientes (local e EKS) — sem migração para S3 nativo
- **Autenticação da API:** API key simples via header `X-API-Key`
- **Registry de imagens:** ECR desde o início, inclusive no cluster local (`kind`)
- **Estrutura ECR:** um repositório por serviço (`dbt-project`, `api-service`, `spark-jobs`) — não usar repo único com tags por serviço
- **Tag de imagem:** Git SHA (ex: `a1b2c3d`) — nunca `latest`; `values.yaml`/CRDs sempre referenciam o SHA exato
- **Postgres:** dedicado por componente (Airflow, Airbyte, Hive Metastore cada um com sua própria instância) — sem Postgres compartilhado
- **DAGs do Airflow:** empacotadas em imagem Docker (mesmo padrão de CI/CD do dbt/API/Spark) — sem git-sync sidecar
- **Fonte de exemplo (Airbyte):** um banco Postgres de exemplo (sample DB), usado para validar o pipeline ponta a ponta na Fase 1
- **CI/CD:** GitHub Actions para todos os pipelines de build/push/deploy (dbt, API, Spark, Airflow)

## Estrutura do repositório
```
specs/                  # specs formais (fonte da verdade do que construir)
  TEMPLATE-spec.md       # modelo para novos specs
  SPEC-XXX-nome.md        # spec "Specify" — o quê e critério de aceite
  SPEC-XXX-nome.plan.md   # spec "Plan" — como, gerado e aprovado antes do Build
infra/terraform/         # IaC de cloud (EKS, VPC, IAM)
infra/clusters/          # config de cluster local (kind)
bootstrap/argocd/         # instalação do ArgoCD + app-of-apps
charts/                  # values.yaml por componente (chart de terceiros)
apps/local/ apps/eks/     # Applications do ArgoCD por ambiente
code/dbt-project/         # código próprio: dbt
code/api-service/         # código próprio: API FastAPI + DuckDB
code/spark-jobs/          # código próprio: jobs Spark + Iceberg
```

## Workflow obrigatório: Specify → Plan → Implement → Validate

Todo spec passa pelas 4 fases abaixo, **nesta ordem**, com aprovação humana
explícita entre cada uma. Nenhuma fase pula a anterior.

### 1. Specify (já feito para os specs existentes)
O arquivo `specs/SPEC-XXX-nome.md` já existe e contém: contexto, arquivos a
criar, especificação técnica, critério de aceite testável, rollback.
Se o spec ainda não existir, ele precisa ser escrito e aprovado por mim
antes de qualquer plano ser gerado.

### 2. Plan
Comando: `/plan-spec SPEC-XXX-nome`
Gera `specs/SPEC-XXX-nome.plan.md`: lista numerada de tarefas, ordem de
execução, comandos exatos a rodar, riscos identificados. **Não edita nenhum
arquivo do projeto nesta fase.** Eu reviso e aprovo o plano antes de seguir.

### 3. Implement (Build)
Comando: `/implement-spec SPEC-XXX-nome`
Só pode rodar depois que existir um `.plan.md` aprovado para aquele spec.
Executa o plano, tarefa por tarefa. Ao final, roda os comandos de validação
básicos definidos no próprio plano (não a validação formal — essa é a
próxima fase).

### 4. Validate
Comando: `/validate-spec SPEC-XXX-nome`
Roda em **subagent com contexto limpo** — ele recebe apenas o diff das
mudanças e o critério de aceite do spec original, sem o histórico de
raciocínio da implementação. Reporta cada critério individualmente
(passou/falhou) e aponta gaps. Só depois disso o spec é marcado como
concluído no status abaixo.

## Regras gerais
- Nunca aplicar mudanças manuais no cluster (`kubectl apply` direto) — tudo
  via Git + ArgoCD sync.
- Specs de infra sensível (Terraform, IAM, qualquer coisa em `SPEC-016`+ /
  EKS) usam Plan Mode obrigatoriamente e passam por uma etapa extra de
  **Brainstorm** antes do Plan, se houver decisão técnica ainda em aberto
  (ex: topologia de rede, dimensionamento de recursos).
- Critérios de aceite devem ser sempre testáveis por comando
  (`kubectl get`, `curl`, `dbt test`...), nunca subjetivos.

## Status atual
- [x] SPEC-001: bootstrap local + ArgoCD — Implementado (EC2)
- [x] SPEC-002: ECR — Implementado (4 repos: dbt-project, api-service, spark-jobs, airflow-dags)
- [x] SPEC-003: MinIO — Implementado (buckets bronze, warehouse, silver, gold, airbyte-storage)
- [x] SPEC-004: Hive Metastore — Implementado (PostgreSQL dedicado, apenas para operações internas)
- [x] SPEC-005: Airflow — Implementado (v3.3.0, KubernetesExecutor)
- [x] SPEC-006: Airbyte — Implementado (com PostgreSQL dedicado e sample source)
- [x] SPEC-007: Trino — Implementado (v480, catálogos: iceberg, hive_bronze, postgres_source)
- [x] SPEC-008: dbt — Implementado (Movielens, dbt-trino, 13 models staging/silver/gold)
- [x] SPEC-009: DAG principal — Implementado (cria external tables + dbt via Cosmos)
- [x] SPEC-010: API — Implementado (FastAPI + DuckDB lendo gold Iceberg do warehouse)
- [x] SPEC-011: Metabase — Implementado (BI conectado ao Trino)
- [x] SPEC-012: Observabilidade — Implementado (kube-prometheus-stack + Grafana)
- [x] SPEC-013: OpenMetadata — Implementado (catálogo + linhagem)
- [x] SPEC-014: Terraform EKS — Implementado (cluster `data-platform-eks`, K8s 1.32, 4x t3.large (ampliado de 3 em 2026-09-23: saturação de CPU), us-east-2; validado 2026-09-22, 7/7 critérios)
- [x] SPEC-015: Overlays EKS — Implementado (17→20 Applications conforme evoluiu); validado 2026-09-23, 5/5 critérios (subagent independente, pipeline Airbyte→Airflow→dbt→API disparado de ponta a ponta + query real no Trino)
- [x] SPEC-016: CI/CD (imagens) — Implementado; validado 2026-09-24, 9/9 critérios (subagent independente, pushes reais nos 3 workflows + teste quebrado provando o critério de gate)
- [ ] SPEC-017: CI/CD (infraestrutura/Terraform) — Implement concluído 2026-09-24 (Makefile em sub-alvos + infra-bootstrap.yml); aguardando Secrets do usuário para rodar de verdade, antes do Validate

(Atualizar esta seção ao final de cada fase de Validate bem-sucedida.)
