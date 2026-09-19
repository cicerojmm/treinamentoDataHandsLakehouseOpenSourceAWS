# SPEC-005: Airflow com KubernetesExecutor

**Fase do projeto:** 1 — Core de Infraestrutura
**Pré-requisitos:** SPEC-001, SPEC-002 (ECR, para a imagem com DAGs)
**Bloqueia:** SPEC-006 (Airbyte, orquestrado por DAG), SPEC-009 (DAG principal), SPEC-015 (Great Expectations)
**Status:** Specify

---

## 1. Contexto
Orquestrador central da plataforma. Decisão fechada: DAGs empacotadas em
imagem Docker própria (mesmo padrão de CI/CD de dbt/API/Spark), não via
git-sync — ou seja, o Airflow em si é chart oficial, mas a imagem do
scheduler/workers é customizada para incluir o código das DAGs.

## 2. Arquivos a criar
```
charts/airflow/
└── values-local.yaml
code/airflow-dags/
├── Dockerfile                  # FROM apache/airflow:<versao>, COPY dags/
├── dags/
│   └── example_healthcheck_dag.py
└── requirements.txt             # providers extras (ex: apache-airflow-providers-cncf-kubernetes)
apps/local/airflow-postgres-app.yaml
apps/local/airflow-app.yaml
```

## 3. Especificação técnica

### 3.1 Postgres dedicado
Instância própria para o metadata DB do Airflow (decisão fechada —
Postgres dedicado por componente).

### 3.2 Imagem customizada
`code/airflow-dags/Dockerfile` parte da imagem oficial do Airflow e
copia o diretório `dags/` para dentro da imagem. Essa imagem é publicada
no repositório ECR `data-platform/airflow-dags` (SPEC-002), taggeada por
Git SHA (decisão fechada), e referenciada no `values-local.yaml` do
chart do Airflow.

### 3.3 Executor
`KubernetesExecutor` — cada task roda como Pod próprio no cluster,
usando a mesma imagem customizada (garante que o código da DAG está
disponível no worker Pod).

### 3.4 DAG de exemplo
Uma DAG mínima (`example_healthcheck_dag.py`) que apenas valida que o
Airflow consegue: (a) agendar uma task, (b) rodar um `KubernetesPodOperator`
simples (ex: `echo "ok"`), confirmando que o executor está funcional antes
de orquestrar componentes reais nos specs seguintes.

## 4. Ordem de execução esperada
```
1. Build + push manual da imagem inicial (antes do CI/CD existir, SPEC-011)
2. ArgoCD sincroniza airflow-postgres-app
3. ArgoCD sincroniza airflow-app (referenciando a imagem no ECR + ecr-pull-secret do SPEC-002)
```

## 5. Critério de Aceite
1. `kubectl get pods -n orchestration` mostra scheduler, webserver (ou API server) e triggerer em `Running`
2. UI do Airflow acessível via port-forward, mostra a DAG `example_healthcheck_dag`
3. Disparar a DAG manualmente resulta em execução bem-sucedida (status verde) e a task via `KubernetesPodOperator` cria um Pod efêmero visível em `kubectl get pods -n orchestration` durante a execução
4. Alterar o código da DAG, rebuildar a imagem com novo SHA, atualizar a tag no `values-local.yaml` e re-sincronizar via ArgoCD reflete a mudança na UI do Airflow

## 6. Rollback / Recuperação
Reverter a tag da imagem no `values-local.yaml` para o SHA anterior e
deixar o ArgoCD sincronizar — rollback é uma operação Git, não manual no
cluster.

## 7. Fora de escopo
- DAGs reais de orquestração de negócio (Airbyte, dbt) — SPEC-009
- CI/CD automatizado do build/push da imagem — SPEC-011 (aqui o primeiro
  build é manual, só para validar o spec)

## 8. Decisões assumidas
- Versão do Airflow: usar a última versão estável 2.x compatível com o
  provider `cncf-kubernetes` no momento da implementação — confirmar no Plan
- Componentes de UI: usar o padrão do chart oficial (webserver clássico
  ou novo API server, dependendo da versão) — decidir no Plan conforme
  a versão escolhida
