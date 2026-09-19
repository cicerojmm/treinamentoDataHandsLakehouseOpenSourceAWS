# Plataforma de Dados Open Source

Plataforma de dados moderna em Kubernetes usando ferramentas open source.

## Arquitetura

```
Airbyte → Airflow → MinIO → dbt + Trino → API (DuckDB) → Metabase
                                        ↘ Spark + Iceberg
```

Componentes de suporte: Grafana, OpenMetadata, Great Expectations

## Pré-requisitos

- Docker 24.x+
- kind 0.23.x+
- kubectl 1.29.x+
- Helm 3.14.x+

## Quick Start (Local)

```bash
# Subir o cluster e ArgoCD
make bootstrap-local

# Acessar UI do ArgoCD
make argocd-ui

# Obter senha do admin
make argocd-password

# Destruir tudo e recomeçar
make destroy-local
```

## Estrutura do Repositório

```
specs/                    # Especificações formais
infra/clusters/           # Configuração de clusters (kind)
bootstrap/argocd/         # Instalação do ArgoCD
apps/local/               # Applications do ArgoCD (ambiente local)
charts/                   # Values para charts Helm
code/                     # Código próprio (dbt, API, Spark)
```

## GitOps

Todas as mudanças são feitas via Git. O ArgoCD sincroniza automaticamente
os recursos definidos em `apps/local/` para o cluster.

Nunca use `kubectl apply` diretamente — sempre via commit + push.
