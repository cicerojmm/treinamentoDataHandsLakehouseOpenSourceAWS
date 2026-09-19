# SPEC-006: Airbyte + Conector de Exemplo

**Fase do projeto:** 1 — Core de Infraestrutura
**Pré-requisitos:** SPEC-003 (MinIO, destino da ingestão)
**Bloqueia:** SPEC-009 (DAG principal, orquestra o sync do Airbyte)
**Status:** Specify

---

## 1. Contexto
Camada de ingestão. Decisão fechada: a fonte de exemplo usada para
validar o pipeline ponta a ponta é um **banco Postgres de exemplo**
(sample DB), sincronizado até o bucket `raw` do MinIO.

## 2. Arquivos a criar
```
charts/airbyte/
└── values-local.yaml
apps/local/airbyte-postgres-app.yaml   # Postgres dedicado do Airbyte (config/state)
apps/local/airbyte-sample-source-app.yaml  # Postgres de exemplo, fonte de dados
apps/local/airbyte-app.yaml
docs/runbooks/airbyte-connector-setup.md   # passo a passo de config via UI/API
```

## 3. Especificação técnica

### 3.1 Postgres dedicado do Airbyte
Instância própria para configuração/estado interno do Airbyte (decisão
fechada — Postgres dedicado por componente). Não confundir com o
Postgres de exemplo (fonte de dados).

### 3.2 Postgres de exemplo (fonte)
Uma segunda instância Postgres, populada com um dataset de exemplo
(ex: dataset `pagila` ou `northwind`, amplamente usados para testes),
representando um "sistema de origem" fictício.

### 3.3 Conector
- **Source**: Postgres (o Postgres de exemplo acima), via CDC ou sync
  incremental simples (decidir no Plan conforme necessidade de teste)
- **Destination**: S3 destination connector do Airbyte, apontando para
  o MinIO (`raw` bucket), configurado com endpoint customizado
  (path-style, credenciais do MinIO)
- Configuração inicial feita via UI do Airbyte (documentar passo a passo
  em `docs/runbooks/airbyte-connector-setup.md`) — automação via
  Terraform provider do Airbyte é candidato a spec futuro, não aqui

## 4. Ordem de execução esperada
```
1. ArgoCD sincroniza airbyte-postgres-app e airbyte-sample-source-app
2. ArgoCD sincroniza airbyte-app
3. Configuração manual do conector via UI (documentada no runbook)
4. Disparo manual do primeiro sync para validar
```

## 5. Critério de Aceite
1. `kubectl get pods -n ingestion` mostra todos os pods do Airbyte em `Running`
2. UI do Airbyte acessível via port-forward
3. Conector Postgres → MinIO configurado e testado (botão "Test connection" verde na UI)
4. Sync manual disparado resulta em arquivos aparecendo em `mc ls minio-local/raw/`
5. Dados no bucket `raw` correspondem ao conteúdo real das tabelas do Postgres de exemplo (validação por contagem de linhas ou amostra)

## 6. Rollback / Recuperação
Reconfigurar o conector do zero via UI é rápido — estado crítico está no
Postgres dedicado do Airbyte, que pode ser recriado sem perda relevante
em ambiente de desenvolvimento.

## 7. Fora de escopo
- Orquestração do sync via Airflow (isso é o SPEC-009 — aqui o sync é
  disparado manualmente só para validar que o pipeline técnico funciona)
- Automação da configuração do conector via API/Terraform

## 8. Decisões pendentes (confirmar no Plan)
- Qual dataset de exemplo usar exatamente (pagila, northwind, ou outro)
- Sync incremental vs full refresh para o teste inicial — recomendo full
  refresh na primeira validação, por simplicidade
