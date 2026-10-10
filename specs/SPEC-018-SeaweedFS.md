# SPEC-018: SeaweedFS (object storage S3-compatível, coexistindo com o MinIO)

**Fase do projeto:** 1 — Core de Infraestrutura (evolução do storage)
**Pré-requisitos:** SPEC-003 (MinIO/AIStor), SPEC-015 (overlays EKS), SPEC-017 (CI/CD de infraestrutura)
**Bloqueia:** specs futuros de migração por consumidor (Trino/Iceberg, Hive Metastore, Airbyte, API, Airflow, OpenMetadata)
**Status:** Specify (aprovado) — plano em `SPEC-018-SeaweedFS.plan.md`

> **Atenção — EKS:** este spec toca o ambiente EKS (SPEC-016+). Pelo
> CLAUDE.md, o Plan deve ser gerado em **Plan Mode** e, havendo decisões
> abertas (seção 10), passa antes por **Brainstorm**.
> **Decisão fechada afetada:** CLAUDE.md afirma "MinIO em todos os
> ambientes, sem migração". Este spec traz justificativa nova (seção 1);
> se aprovado, a decisão deve ser reescrita no CLAUDE.md como "MinIO e
> SeaweedFS coexistem durante a migração; SeaweedFS é o destino final".

---

## 1. Contexto e motivação
O MinIO Community deixou de ser utilizável sem licença: a MinIO Inc. trancou
o pull anônimo das imagens legadas (2026-09-24) e o servidor passou a exigir
licença (AIStor Free, single-node, via subnet.min.io) — ver SPEC-003. O
projeto migrou para o AIStor, mas isso nos deixa dependentes de uma licença
gratuita de um único vendor, com restrições (single-node) e sem caminho
open source garantido.

O **SeaweedFS** (licença Apache 2.0, sem licença comercial) oferece:
API S3 compatível, escala horizontal (master + volume servers + filer),
e roda em Kubernetes via Helm chart oficial.

Objetivo deste spec: **provisionar o SeaweedFS no kind (local) e no EKS,
via ArgoCD, em paralelo ao MinIO, com os buckets `bronze` e `warehouse`
criados no bootstrap.** Nenhum consumidor é migrado aqui.

### 1.1 Estratégia de migração (contexto, fora do escopo deste spec)
A migração é **incremental, por consumidor**. O MinIO permanece de pé,
com seus dados, até que todos os dados e consumidores estejam no
SeaweedFS. Só então um spec final removerá o MinIO.

```
Hoje:         [Airbyte|Trino|HMS|API|Airflow|OM] ──► MinIO
Este spec:    [Airbyte|Trino|HMS|API|Airflow|OM] ──► MinIO        SeaweedFS (vazio, buckets criados)
Migração:     consumidores migrando 1 a 1        ──► SeaweedFS    MinIO (cada vez menos usado)
Final:        todos ──► SeaweedFS                                  MinIO removido (spec futuro)
```

## 2. Escopo
Dentro:
- Deploy do SeaweedFS (master, volume, filer, gateway S3) em local e EKS
- Padrão ArgoCD (App-of-Apps, sync waves, Helm de terceiros + Job de setup)
- Bootstrap idempotente dos buckets `bronze` e `warehouse`
- Credenciais S3 próprias do SeaweedFS (distintas das do MinIO)
- Script de verificação e documentação (README + runbook)

Fora (seção 8): migração de consumidores/dados, remoção do MinIO,
alta disponibilidade, replicação, TLS, Ingress/ELB público.

## 3. Arquivos a criar / alterar

### 3.1 Criar
```
apps/local/seaweedfs-app.yaml              # Application Helm (chart oficial) — kind
apps/local/seaweedfs-setup-app.yaml        # Application kustomize: Job de buckets — kind
apps/eks/seaweedfs-app.yaml                # idem — EKS
apps/eks/seaweedfs-setup-app.yaml          # idem — EKS
charts/seaweedfs-local-setup/
├── kustomization.yaml                     # configMapGenerator (lista de buckets)
└── create-buckets-job.yaml                # Job aws-cli (padrão do minio-*-setup)
charts/seaweedfs-eks-setup/
├── kustomization.yaml
└── create-buckets-job.yaml
scripts/verify-seaweedfs-buckets.sh        # confere buckets (espelha verify-minio-buckets.sh)
docs/runbooks/seaweedfs-setup.md           # operação: port-forward, aws cli, troubleshooting
```

### 3.2 Alterar
```
bootstrap/namespaces.yaml                  # nenhum namespace novo (usa data-platform)
Makefile                                   # verify-seaweedfs-buckets.sh junto do verify-minio-buckets.sh no verify-eks
.github/workflows/infra-bootstrap.yml      # idem (se o bootstrap criar secrets no workflow)
README.md                                  # seção SeaweedFS + tabela de endpoints
CLAUDE.md                                  # decisão fechada (storage) + Status (na fase Validate)
```

> Nenhum arquivo do MinIO é alterado. Coexistência = nenhuma regressão no
> que já funciona.

## 4. Especificação técnica

### 4.1 Topologia e nomes
Namespace: `data-platform` (junto do MinIO). Release Helm: `seaweedfs`.
Nomes de Service esperados pelo chart oficial (**confirmar no Plan** com
`helm template`):

| Componente | Service | Porta | Função |
|---|---|---|---|
| Master | `seaweedfs-master` | 9333 (gRPC 19333) | topologia / alocação de volumes |
| Volume | `seaweedfs-volume` | 8080 (gRPC 18080) | armazena os dados |
| Filer | `seaweedfs-filer` | 8888 (gRPC 18888) | namespace de arquivos/metadados |
| S3 gateway | `seaweedfs-s3` | **8333** | API S3 (o que os consumidores usam) |

Endpoints internos de S3 (equivalentes aos `minio-*-hl` atuais):
- **EKS:** `http://seaweedfs-s3.data-platform.svc.cluster.local:8333`
- **Local:** `http://seaweedfs-s3.data-platform.svc.cluster.local:8333`
  (mesmo DNS; os dois clusters são independentes)

Todos os acessos S3 usam **path-style** (`http://host:8333/<bucket>/<key>`),
como já é necessário para o MinIO.

### 4.2 Application do chart (Helm de terceiros)
Mesmo padrão de `apps/*/minio-objectstore-app.yaml`:
- `repoURL: https://seaweedfs.github.io/seaweedfs/helm`, `chart: seaweedfs`
- `targetRevision` **fixa** (nunca range/`latest`); versão exata definida
  no Plan via `helm search repo seaweedfs --versions`
- Imagem com **tag fixa** (nunca `latest`), anotada no `values` inline
- `destination.namespace: data-platform`, `CreateNamespace=true`
- `syncPolicy.automated: {prune: true, selfHeal: true}`
- Anotação `argocd.argoproj.io/sync-wave: "2"` (mesma onda do MinIO)

Esqueleto de values (valores finais calibrados no Plan):

```yaml
global:
  enableSecurity: false            # sem mTLS interno por ora (ver §8)
master:
  replicas: 1
  data: { type: persistentVolumeClaim, size: 5Gi, storageClass: <sc> }
  resources: { requests: { cpu: 10m, memory: 64Mi }, limits: { memory: 256Mi } }
volume:
  replicas: 1
  dataDirs:
    - { name: data1, type: persistentVolumeClaim, size: <20Gi|50Gi>, storageClass: <sc>, maxVolumes: 0 }
  resources: { requests: { cpu: 20m, memory: 128Mi }, limits: { memory: 512Mi } }
filer:
  replicas: 1
  data: { type: persistentVolumeClaim, size: 5Gi, storageClass: <sc> }   # metadados (leveldb2)
  s3: { enabled: false }           # S3 fica no pod dedicado abaixo
  resources: { requests: { cpu: 20m, memory: 128Mi }, limits: { memory: 512Mi } }
s3:                                # gateway S3 dedicado (Deployment)
  enabled: true
  port: 8333
  enableAuth: true
  credentials: { admin: { accessKey: <novo>, secretKey: <novo> } }
  resources: { requests: { cpu: 10m, memory: 64Mi }, limits: { memory: 256Mi } }
```

| Parâmetro | Local (kind) | EKS |
|---|---|---|
| `storageClass` | `standard` | `gp3` |
| Volume de dados | 20Gi | 50Gi (igual ao MinIO) |
| Réplicas | 1 de cada | 1 de cada |
| Replicação de volume | `000` (sem réplica) | `000` (sem réplica) |

> **Risco de capacidade (EKS):** o cluster já saturou CPU uma vez (3→4
> nós, SPEC-014). Requests acima são mínimos medidos-por-estimativa; o
> Plan deve medir a ocupação atual (`kubectl top nodes`) e confirmar que
> cabem 4 pods novos sem forçar novo nó. Se não couber, é decisão
> do usuário (subir nó vs. reduzir componentes) — não decidir sozinho.

### 4.3 Credenciais
- O gateway S3 roda com autenticação ligada (`s3.enableAuth: true`); a
  identidade admin é declarada em `s3.credentials.admin.{accessKey,secretKey}`
  nos `values` do Application (o chart gera o Secret de config).
- **Credenciais diferentes das do MinIO** e diferentes entre local e EKS
  (evita que um consumidor aponte para o endpoint errado e "funcione" por acaso).
- **Estáticas no Git**, mesmo tratamento já dado ao MinIO (ambiente de testes,
  sem External Secrets). Chaves novas e aleatórias (`openssl rand`).
- O Job de buckets usa as mesmas chaves como `env` literal (padrão do
  `create-buckets-job` do MinIO).
- Consumidores em **outros namespaces** (`ingestion`, `query-engine`,
  `orchestration`) receberão credenciais nos specs de migração, não aqui.

### 4.4 Bootstrap de buckets (`bronze`, `warehouse`)
Segue exatamente o padrão `charts/minio-*-setup`:
- `Job` com hook ArgoCD `Sync` + `hook-delete-policy: BeforeHookCreation`
- `initContainer` (`busybox`) aguardando `nc -z seaweedfs-s3.data-platform.svc.cluster.local 8333`
- Container `amazon/aws-cli` (tag fixa definida no Plan) com
  `--endpoint-url http://seaweedfs-s3.data-platform.svc.cluster.local:8333`
- Credenciais via `secretKeyRef` (nunca `value:` literal)
- Loop idempotente: `head-bucket || create-bucket` para cada item da lista
- Lista vinda do `configMapGenerator` (`buckets=bronze warehouse`) — mudar a
  lista no Git re-dispara o Job (mesma mecânica do MinIO)
- `backoffLimit: 20`, `restartPolicy: OnFailure`
- `Application` própria (`seaweedfs-setup`) com **sync-wave 3**

Buckets: **somente `bronze` e `warehouse`.** `silver`, `gold` e
`airbyte-storage` existem no MinIO mas **não** são criados aqui; entram
no spec do consumidor que precisar deles.

> **Por que manter os mesmos nomes de bucket do MinIO:** as tabelas
> Iceberg guardam caminhos absolutos `s3://warehouse/...` nos metadados e
> as external tables do Hive usam `s3://bronze/...`. Como o bucket
> tem o mesmo nome nos dois storages, o catálogo não precisa ser reescrito;
> só o *endpoint* do filesystem S3 do consumidor muda na migração.

### 4.5 Ordem de sync (sync waves)
```
wave 2 : minio-objectstore, seaweedfs        (paralelos, independentes)
wave 3 : minio-eks-setup,  seaweedfs-setup   (cada um espera o seu S3 via initContainer)
wave 4+: hive-metastore, trino, ...          (inalterados — continuam no MinIO)
```
Nada depende do SeaweedFS neste spec; uma falha nele **não pode** bloquear
o resto da plataforma (ver critério 8).

### 4.6 Acesso de operador
Sem Ingress/ELB. Console/API via port-forward:
```bash
kubectl port-forward -n data-platform svc/seaweedfs-s3 8333:8333
kubectl port-forward -n data-platform svc/seaweedfs-filer 8888:8888   # UI do filer
kubectl port-forward -n data-platform svc/seaweedfs-master 9333:9333  # UI do master
aws --endpoint-url http://localhost:8333 s3 ls
```
(No EKS, usar `--context=data-platform-eks`.) As portas locais 8333/8888/9333
não colidem com as já documentadas (8080, 8081, 9090).

## 5. Ordem de execução
```
1. Merge do spec/plano aprovados; branch de implementação
2. (sem passo manual de Secret — credenciais vêm dos values versionados)
3. Commit dos Applications + charts de setup → push → ArgoCD sync
4. ArgoCD: seaweedfs (wave 2) → seaweedfs-setup (wave 3, Job de buckets)
5. scripts/verify-seaweedfs-buckets.sh
6. Validação de coexistência (MinIO intacto) — critérios 7 e 8
```
Local: via `make run-local`. EKS: via `make bootstrap-eks` /
`infra-bootstrap.yml` (idempotente — rerun não deve alterar nada).

## 6. Critérios de Aceite (todos testáveis por comando)
Executar em **ambos** os ambientes (`--context=data-platform-eks` e kind).

1. `kubectl get application seaweedfs seaweedfs-setup -n argocd` → ambos `Synced`/`Healthy`
2. `kubectl get pods -n data-platform -l app.kubernetes.io/name=seaweedfs` → master, volume, filer (e s3, se separado) em `Running`/`Ready`, 0 restarts após 5 min
3. `kubectl get pvc -n data-platform | grep -i seaweed` → todos `Bound`
4. Com port-forward: `aws --endpoint-url http://localhost:8333 s3 ls` lista **exatamente** `bronze` e `warehouse`
5. Round-trip: `aws s3 cp teste.txt s3://bronze/_smoke/teste.txt` → `aws s3 cp s3://bronze/_smoke/teste.txt -` devolve o mesmo conteúdo → `aws s3 rm` ok. Idem em `warehouse`
6. Sem credencial (ou com credencial errada) o acesso é negado: `aws s3 ls` com chaves inválidas → `AccessDenied`/`InvalidAccessKeyId`
7. **Coexistência:** `scripts/verify-minio-buckets.sh` continua passando (5 buckets do MinIO presentes) e `kubectl get objectstore -n data-platform` segue `Ready`
8. **Sem regressão:** no EKS, todas as Applications pré-existentes continuam `Synced`/`Healthy` (19/19 + as 2 novas = 21/21); `kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded` sem pods travados novos; no local, as Applications do `apps/local` idem
9. **Idempotência:** reexecutar o Job de buckets (`kubectl delete job seaweedfs-create-buckets -n data-platform` + sync) termina com sucesso sem erro de "bucket já existe"
10. **Persistência:** `kubectl delete pod` do volume server e do filer → após `Ready`, o objeto do critério 5 (gravado antes) continua legível
11. As chaves do SeaweedFS diferem das do MinIO: nenhuma chave de `apps/*/minio-objectstore-app.yaml` aparece em `apps/*/seaweedfs*` nem em `charts/seaweedfs-*` (e as de local ≠ EKS)
12. `scripts/verify-seaweedfs-buckets.sh` retorna exit 0 em ambos os ambientes

## 7. Rollback / Recuperação
- **Reverter o spec inteiro:** remover `seaweedfs*-app.yaml` de `apps/{local,eks}` via Git (o
  app-of-apps com `prune: true` remove os recursos). O MinIO não é afetado.
- **PVCs:** Helm/ArgoCD não apagam PVCs de StatefulSet por padrão — apagar
  manualmente (`kubectl delete pvc -n data-platform -l app.kubernetes.io/name=seaweedfs`)
  só se os dados forem descartáveis. No SeaweedFS ainda **não há dado
  de produção** até o primeiro spec de migração.
- **Local:** recriar o cluster (`make destroy-local && make run-local`) é aceitável.
- **EKS:** nunca apagar PVC/volume do SeaweedFS depois que houver dado migrado
  sem backup/cópia equivalente no MinIO (que continua sendo a fonte da verdade
  durante a migração — por isso ele não é removido).

## 8. Fora de escopo
- Migração de **qualquer** consumidor ou dado (Trino/Iceberg, Hive Metastore,
  Airbyte, API/DuckDB, Airflow, OpenMetadata) — um spec por consumidor
- Remoção do MinIO/AIStor e do operator
- Buckets `silver`, `gold`, `airbyte-storage`
- Alta disponibilidade, múltiplos volume servers, replicação de volumes
  (`001`/`010`), erasure coding
- TLS/mTLS (`global.enableSecurity`), Ingress/ELB/DNS público
- Backup e snapshot do filer (metadados) e dos volumes
- ServiceMonitor/dashboards Grafana do SeaweedFS (métricas na porta 9327) —
  spec futuro de observabilidade
- Integração do filer com Postgres/outro backend de metadados (ver §10)
- Espelhamento das imagens no ECR (ver §10)

## 9. Riscos identificados
| Risco | Impacto | Mitigação |
|---|---|---|
| Capacidade do cluster EKS (CPU/mem) | Pods `Pending`, impacto na plataforma | Medir `kubectl top nodes` no Plan; requests mínimos; sync-wave isola a falha |
| Nomes de Service/portas do chart diferirem do esperado | Job de buckets nunca conecta | Plan valida com `helm template` e ajusta §4.1 antes do Build |
| Pull de imagens do Docker Hub (rate limit / mudança de política, como ocorreu com o MinIO) | Pods em `ImagePullBackOff` | Tags fixas; avaliar espelho no ECR (§10); o incidente do MinIO é o precedente |
| Perda do filer (metadados em leveldb no PVC) = perda do namespace de objetos | Dados órfãos | Aceito nesta fase (sem dado de produção); backup entra antes do 1º spec de migração |
| Confusão entre endpoints (mesmos nomes de bucket nos 2 storages) | Consumidor grava no storage errado sem perceber | Credenciais distintas (§4.3), DNS distinto, runbook com tabela de endpoints, specs de migração trocam endpoint+credencial juntos |
| Diferenças de compatibilidade S3 (Iceberg commit, multipart, listagem) | Falhas só aparecem na migração | Smoke test do critério 5 agora; spec de migração do Trino inclui teste de escrita Iceberg + `dbt build` |
| Credencial versionada no Git | Vazamento do repo expõe o storage | Aceito (ambiente de testes, igual ao MinIO); chaves novas e distintas; rotacionar antes de dado real |

## 10. Decisões (resolvidas no Plan, 2026-10-10)
> 1 = gateway S3 **dedicado**; 2 = **leveldb2** em PVC; 3 = **Docker Hub** com tag fixa (`chrislusf/seaweedfs:4.48`, chart `4.48.0`); 4 = credenciais **estáticas no Git**; 5 e 6 = valores propostos abaixo, aceitos. Texto original mantido para registro.

1. **Gateway S3 embutido no filer vs. Deployment `s3` dedicado.** Dedicado
   isola recursos/reinícios do S3 e é o que o chart recomenda p/ produção; embutido economiza 1 pod
   (relevante pela folga de CPU no EKS). *Sugestão:* dedicado se couber, senão embutido.
2. **Backend de metadados do filer:** `leveldb2` em PVC (padrão, simples,
   1 réplica) vs. PostgreSQL. A regra "Postgres dedicado por componente"
   existe; usar Postgres adicionaria uma instância e permitiria
   filer >1 réplica. *Sugestão:* leveldb2 agora, reavaliar antes da migração.
3. **Origem das imagens:** Docker Hub direto (`chrislusf/seaweedfs`, mais simples)
   vs. espelhar no ECR (consistente com "ECR desde o início", imune a
   mudança de política do Docker Hub). *Sugestão:* Docker Hub com tag fixa agora; ECR
   no spec de hardening.
4. **Geração das credenciais:** script `ensure-*` com chaves aleatórias
   (proposto, nada em texto puro no Git) vs. estático no Git (como os
   `create-buckets-job` atuais do MinIO fazem hoje). *Sugestão:* script.
5. **Dimensionamento do volume no EKS:** 50Gi (igual ao MinIO) — suficiente
   enquanto o MinIO segue sendo a fonte de dados; reavaliar ao migrar.
6. **Nome do Job/Application de setup:** `seaweedfs-setup` vs.
   `seaweedfs-eks-setup`/`seaweedfs-local-setup` (o MinIO usa sufixo por ambiente
   porque os charts são separados; manter o mesmo padrão é o default proposto).

## 11. Plano de migração incremental (referência para os próximos specs)
Ordem sugerida, do menor para o maior risco; cada item = um spec próprio
com Specify→Plan→Implement→Validate:

| # | Consumidor | O que muda | Observação |
|---|---|---|---|
| 1 | Cópia de dados (job `rclone`/`aws s3 sync` MinIO→SeaweedFS) | nada nos consumidores | pré-requisito dos demais; repetível/idempotente |
| 2 | API (DuckDB) | `MINIO_ENDPOINT` + credencial | leitura do gold; baixo risco |
| 3 | Airflow (novas DAGs) | conexão S3 | ex.: DAGs novas já nascem no SeaweedFS |
| 4 | Airbyte | `storage` e destino bronze | dependia do bucket `airbyte-storage` + `bronze` |
| 5 | Hive Metastore | `fs.s3a.endpoint` | external tables da bronze |
| 6 | Trino (`iceberg` + `hive_bronze`) | endpoint do filesystem S3 nativo | maior risco: commits Iceberg; fazer por último, com `dbt build` completo como validação |
| 7 | OpenMetadata | conector S3 | manifest `openmetadata.json` |
| 8 | Remoção do MinIO | deletar operator/ObjectStore | só com todos os buckets/consumidores migrados e validados |

## 12. Notas para a fase de Plan
- Gerar o plano em **Plan Mode** e **sem editar nada** (regra do CLAUDE.md).
- Antes de qualquer tarefa: `helm repo add seaweedfs ... && helm template` para
  fixar versão do chart, tag da imagem, nomes de Service e chaves exatas do `values`.
- Verificar `kubectl top nodes` no EKS e o `storageClass` real no kind (`standard`).
- Atualizar o Status do CLAUDE.md somente após `/validate-spec` bem-sucedido.
