# SPEC-004: Hive Metastore Dedicado

**Fase do projeto:** 1 — Core de Infraestrutura
**Pré-requisitos:** SPEC-003 (MinIO)
**Bloqueia:** SPEC-007 (Trino), SPEC-012 (Spark), SPEC-008 (dbt, indiretamente via Trino)
**Status:** Specify

---

## 1. Contexto
Catálogo único compartilhado por Trino, Spark e dbt (decisão fechada) —
evita dessincronização de schema entre engines. Este spec sobe o Hive
Metastore com Postgres dedicado (decisão fechada) como backend.

## 2. Arquivos a criar
```
charts/hive-metastore/
├── values-local.yaml
└── Dockerfile                  # se não houver chart oficial satisfatório,
                                  # empacotar imagem própria do metastore
apps/local/hive-metastore-postgres-app.yaml
apps/local/hive-metastore-app.yaml
```

## 3. Especificação técnica

### 3.1 Postgres dedicado
Instância Postgres exclusiva do Hive Metastore (decisão fechada — sem
compartilhamento com Airflow/Airbyte), via chart `bitnami/postgresql`
ou subchart equivalente, no namespace `data-platform`.

### 3.2 Hive Metastore
- Configurar `hive.metastore.warehouse.dir` apontando para
  `s3a://gold/warehouse` no MinIO (endpoint do SPEC-003)
- Configurar client S3A com endpoint MinIO, path-style access habilitado
  (obrigatório para MinIO, diferente do S3 real)
- Schema do metastore inicializado via `schematool -initSchema` (rodar
  como Job de inicialização, uma vez)
- Expor via Service interno na porta padrão do Thrift (9083)

## 4. Ordem de execução esperada
```
1. ArgoCD sincroniza hive-metastore-postgres-app
2. Job de init schema roda contra o Postgres novo
3. ArgoCD sincroniza hive-metastore-app (aponta para o Postgres + MinIO)
```

## 5. Critério de Aceite
1. `kubectl get pods -n data-platform` mostra o pod do metastore em `Running`
2. Teste de conexão Thrift: `nc -zv hive-metastore.data-platform.svc.cluster.local 9083` retorna sucesso
3. Criar uma tabela de teste via cliente Hive/Beeline e confirmar que ela
   aparece fisicamente como metadata no bucket `curated` do MinIO
4. Reiniciar o pod do metastore não perde o schema (dados persistem no
   Postgres, não no pod)

## 6. Rollback / Recuperação
Se o schema corromper, `schematool -initSchema` pode ser rerodado contra
um Postgres limpo — aceitável em desenvolvimento, nunca em produção sem
backup.

## 7. Fora de escopo
- Alta disponibilidade do metastore (réplicas) — não necessário na Fase 1
- Backup automatizado do Postgres — avaliar antes do EKS (SPEC-017)

## 8. Decisões pendentes (precisa confirmar antes do Plan)
- Versão exata do Hive Metastore precisa ser compatível simultaneamente
  com a versão do Trino (SPEC-007) e do Spark+Iceberg runtime (SPEC-012)
  que ainda serão escolhidas — recomendo fechar as 3 versões juntas no
  Plan deste spec, consultando a matriz de compatibilidade oficial de
  cada projeto no momento da implementação (não fixar aqui para evitar
  versão desatualizada)
