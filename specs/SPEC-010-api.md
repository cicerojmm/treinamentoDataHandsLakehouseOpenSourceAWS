# SPEC-010: API FastAPI + DuckDB (Serving)

**Fase do projeto:** 2 — Camada de Código
**Pré-requisitos:** SPEC-007 (Trino/Iceberg), SPEC-008 (dbt, gera os marts consumidos)
**Bloqueia:** nenhum spec técnico direto — é ponta de consumo
**Status:** Specify

---

## 1. Contexto
Camada de serving para consumo externo dos dados curados. Decisões
fechadas: autenticação via API key simples (header `X-API-Key`),
DuckDB lendo diretamente do MinIO/Iceberg sem persistência local de
estado.

## 2. Arquivos a criar
```
code/api-service/
├── Dockerfile
├── app/
│   ├── main.py
│   ├── auth.py                  # middleware de validação da API key
│   ├── routers/
│   │   └── datasets.py
│   ├── services/
│   │   └── duckdb_client.py
│   └── config.py
├── tests/
├── k8s/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── hpa.yaml
│   └── secret-apikey.yaml        # referência ao Secret, não o valor
└── pyproject.toml
```

## 3. Especificação técnica

### 3.1 DuckDB
Extensões `httpfs` e `iceberg` carregadas na inicialização; endpoint do
MinIO configurado via variável de ambiente. Nenhuma escrita local além
de cache temporário em `/tmp` (pod stateless).

### 3.2 Autenticação
Middleware FastAPI validando `X-API-Key` contra valor armazenado em
Kubernetes Secret. Rotas `/healthz` e `/readyz` isentas (usadas pelos
probes do Kubernetes). Requisição sem chave válida → `401 Unauthorized`.

### 3.3 Endpoints
Definir no Plan o contrato exato de dados (quais tabelas/marts do
dbt são expostas e com qual forma de endpoint — genérico
`/datasets/{nome}` vs endpoints específicos por caso de uso). Este spec
não decide o contrato de produto, só a arquitetura técnica de acesso.

### 3.4 Deployment
Stateless, réplicas ≥ 2, `HorizontalPodAutoscaler` baseado em CPU
(threshold a definir no Plan).

## 4. Ordem de execução esperada
```
1. Build local da imagem
2. Push manual para ECR (data-platform/api-service)
3. Criar Secret com a API key
4. Deploy do Deployment/Service/HPA
```

## 5. Critério de Aceite
1. `/healthz` responde 200 sem necessidade de API key
2. Requisição a um endpoint de dados sem `X-API-Key` retorna 401
3. Requisição com `X-API-Key` válida retorna dados reais de uma tabela
   curada (gerada pelo dbt no SPEC-008)
4. Escalar carga sintética (ex: `hey`/`k6`) dispara o HPA, aumentando
   réplicas visíveis em `kubectl get pods`
5. Tempo de resposta de uma consulta simples fica abaixo de 500ms em
   dataset de teste

## 6. Rollback / Recuperação
Rollback padrão via ArgoCD (reverter tag de imagem). Rotação de API key:
atualizar o Secret + `kubectl rollout restart` (documentar como runbook).

## 7. Fora de escopo
- Autenticação avançada (OAuth2/JWT/IdP) — fica pronto para essa
  evolução futura, não implementado agora
- Rate limiting — avaliar necessidade quando houver consumidores reais

## 8. Decisões pendentes (confirmar antes do Plan)
- **Contrato de dados**: quais tabelas/marts exatamente a API expõe, e
  em que formato de endpoint — isso é decisão de produto, preciso da
  sua definição antes de gerar o Plan deste spec
