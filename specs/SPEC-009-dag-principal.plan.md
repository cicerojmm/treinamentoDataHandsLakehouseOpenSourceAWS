# SPEC-009: DAG Principal — Plano de Implementação

**Status:** Aguardando aprovação

---

## 1. Resumo

Criar a DAG principal que orquestra o pipeline completo:
```
Airbyte sync → dbt build (via Cosmos)
```

## 2. Decisões técnicas

| Decisão | Escolha | Justificativa |
|---------|---------|---------------|
| Agendamento | `@daily` | Suficiente para dados de exemplo, ajustável depois |
| Airbyte provider | `apache-airflow-providers-airbyte>=3.8.0` | Provider oficial para Airflow 3.x |
| dbt execution | Reutilizar Cosmos já configurado | Evita duplicação, DbtTaskGroup integra na DAG |
| Estratégia dbt | `dbt build` (full refresh) | Dados de exemplo pequenos, incremental é melhoria futura |

## 3. Tarefas

### Tarefa 1: Adicionar provider Airbyte
**Arquivo:** `code/airflow-dags/requirements.txt`
**Ação:** Adicionar `apache-airflow-providers-airbyte>=3.8.0`

### Tarefa 2: Criar DAG principal
**Arquivo:** `code/airflow-dags/dags/main_pipeline_dag.py`
**Estrutura:**
```python
AirbyteTriggerSyncOperator → AirbyteJobSensor → DbtTaskGroup (Cosmos)
```

**Configuração:**
- `airbyte_conn_id`: Conexão a ser criada no Airflow UI
- `connection_id`: ID da connection do Airbyte (será obtido da API)
- Retries: 2 com backoff exponencial
- Tags: `["pipeline", "airbyte", "dbt", "movielens"]`

### Tarefa 3: Build e push da imagem
**Comandos:**
```bash
cd code/airflow-dags
docker build -t <ECR>/airflow-dags:<SHA> .
docker push <ECR>/airflow-dags:<SHA>
```

### Tarefa 4: Atualizar values-local.yaml
**Arquivo:** `charts/airflow/values-local.yaml`
**Ação:** Atualizar tag da imagem para novo SHA

### Tarefa 5: Configurar conexão Airbyte no Airflow
**Via UI:** Admin > Connections > Add Connection
- Conn Id: `airbyte_default`
- Conn Type: `Airbyte`
- Host: `airbyte-airbyte-server-svc.data-platform.svc.cluster.local`
- Port: `8001`

### Tarefa 6: Obter Connection ID do Airbyte
**Comando:**
```bash
kubectl port-forward svc/airbyte-airbyte-webapp-svc -n data-platform 8080:8080
# Acessar UI, pegar ID da connection Postgres → MinIO
```

### Tarefa 7: Validar execução
**Ações:**
1. Trigger manual da DAG na UI
2. Verificar 3 tasks verdes em sequência
3. Confirmar dados no MinIO bronze e gold

## 4. Ordem de execução

```
1. Tarefa 1 (requirements.txt)
2. Tarefa 2 (DAG)
3. Tarefa 3 (build/push)
4. Tarefa 4 (values.yaml)
5. ArgoCD sync
6. Tarefa 5 (conexão Airbyte)
7. Tarefa 6 (Connection ID)
8. Tarefa 7 (validação)
```

## 5. Riscos identificados

| Risco | Mitigação |
|-------|-----------|
| Connection ID do Airbyte pode mudar | Usar variável de ambiente ou Airflow Variable |
| Airbyte sync pode demorar | Sensor com timeout configurável (default 1h) |
| dbt pode falhar por dados faltantes | Airbyte sensor garante sync completo antes |

## 6. Comandos de validação

```bash
# DAG aparece no Airflow
kubectl exec -n data-platform deploy/airflow-webserver -- \
  airflow dags list | grep main_pipeline

# Trigger manual
kubectl exec -n data-platform deploy/airflow-webserver -- \
  airflow dags trigger main_pipeline

# Status da última run
kubectl exec -n data-platform deploy/airflow-webserver -- \
  airflow dags list-runs -d main_pipeline
```

## 7. Rollback

Reverter `values-local.yaml` para SHA anterior e sync ArgoCD.

---

**Aprovado?** Aguardando confirmação para implementar.
