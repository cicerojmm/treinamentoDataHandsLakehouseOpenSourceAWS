# PLAN — SPEC-018: SeaweedFS (coexistindo com o MinIO)

**Spec:** `specs/SPEC-018-SeaweedFS.md`
**Status do plano:** Rascunho — aguardando aprovação humana
**Fase:** Plan (nenhum arquivo do projeto foi alterado; só este arquivo foi criado)
**Modo:** envolve EKS → Plan Mode obrigatório (CLAUDE.md, SPEC-016+)

> Nota: o comando foi chamado com `SPEC-018-SeaweedFS.md.md`; o arquivo real é
> `specs/SPEC-018-SeaweedFS.md` e o plano segue o padrão `SPEC-XXX-nome.plan.md`.

---

## 1. Pré-requisitos verificados
| Pré-requisito | Fonte | Situação |
|---|---|---|
| SPEC-003 MinIO/AIStor | CLAUDE.md (Status) | ✅ Implementado |
| SPEC-015 Overlays EKS | CLAUDE.md | ✅ Implementado e validado (5/5) |
| SPEC-017 CI/CD infra | CLAUDE.md | ✅ Implementado e validado (5/5) |
| Cluster EKS `data-platform-eks` acessível | `kubectl top nodes` | ✅ 4 nós respondendo |
| Chart oficial disponível | `helm search repo seaweedfs/seaweedfs` | ✅ chart **4.48.0**, app **4.48**, imagem `chrislusf/seaweedfs:4.48` |
| Nomes de Service (spec §4.1) | `helm template` (verificado) | ✅ `seaweedfs-master:9333`, `seaweedfs-volume:8080`, `seaweedfs-filer:8888`, `seaweedfs-s3:8333` |
| Gateway S3 dedicado | `helm template` com `s3.enabled=true`, `filer.s3.enabled=false` | ✅ gera `Deployment/seaweedfs-s3` |
| Chart suporta `existingConfigSecret` (chave `seaweedfs_s3_config`) e `s3.credentials.admin.{accessKey,secretKey}` | `helm show values` | ✅ |
| StorageClass EKS | `kubectl get sc` | ✅ `gp3` (default) |
| StorageClass local (kind) | cluster kind não está de pé nesta máquina | ⚠️ assumir `standard` (igual ao `apps/local/minio-objectstore-app.yaml`); confirmar no Implement |

Capacidade do EKS (medido agora): CPU 9–27%, **memória 63–76%** por nó.
Requests propostos somam ~0,4 Gi de memória e ~60m de CPU para os 4 pods —
cabem, mas o Implement deve conferir `kubectl describe nodes | grep -A8 Allocated`
(requests alocáveis, não uso) antes do sync no EKS.

## 2. Decisões
### 2.1 Resolvidas (respostas do usuário nesta fase)
| # | Decisão | Escolha |
|---|---|---|
| 1 | Gateway S3 | **Pod dedicado** (`s3.enabled: true`, `filer.s3.enabled: false`) |
| 2 | Metadados do filer | **leveldb2 em PVC** (1 réplica) |
| 3 | Imagens | **Docker Hub, tag fixa** `chrislusf/seaweedfs:4.48` |
| 4 | Credenciais | **Estático no Git** (padrão atual do MinIO) — ver 2.3 |

### 2.2 Assumidas do próprio spec (confirmar ao aprovar)
| # | Decisão | Valor assumido |
|---|---|---|
| 5 | Volume de dados | EKS 10Gi (gp3) / local 10Gi (standard); master 5Gi; filer 5Gi |
| 6 | Nome dos Apps de setup | `seaweedfs-setup` em ambos os ambientes, com charts separados `seaweedfs-{local,eks}-setup` (padrão do MinIO) |

### 2.3 ⚠️ Divergências do spec causadas pela decisão 4 (credenciais estáticas)
O spec foi escrito assumindo script `ensure-seaweedfs-secret.sh`. Com a escolha
"estático no Git", precisam mudar **no spec** (peço aprovação para ajustar na
tarefa T0, antes do Build):
- §3.1: **remover** `scripts/ensure-seaweedfs-secret.sh` e as alterações de `Makefile`/`infra-bootstrap.yml` ligadas a ele
- §4.3: credenciais passam a ser literais nos `values` do App (`s3.credentials.admin`) e no `env` do Job de buckets — **chaves novas e aleatórias, nunca as do MinIO**, para um consumidor não "funcionar por acaso" no endpoint errado
- §6 critério 11 (nenhuma credencial em texto puro) **deixa de valer** → substituir por: "as chaves do SeaweedFS são diferentes das do MinIO (`grep` das chaves do MinIO em `*seaweedfs*` não retorna nada)"
- §9: risco "Secret fora do GitOps" some; entra "credencial versionada no Git" (aceito: ambiente de testes, mesmo tratamento do MinIO)

> Alternativa que mantém o espírito do GitOps sem script: o próprio chart
> gera o Secret a partir de `s3.credentials` — o Job lê via `secretKeyRef`
> em vez de repetir o literal. **Recomendo** isso: o literal fica em 1 lugar por ambiente
> (no `values` do App) e o Job não duplica a credencial. Se aprovado, o Secret
> gerado pelo chart tem nome a confirmar com `helm template` na T2.

## 3. Tarefas
Ordem estrita; `→` indica dependência. Cada tarefa termina com os comandos de
validação básica da seção 5.

### T0 — Ajustar o spec (docs) — sem dependência
- Editar `specs/SPEC-018-SeaweedFS.md` conforme 2.3 e marcar decisões 1–4 como resolvidas na §10.
- Atualizar §4.2 com chart `4.48.0`, imagem `chrislusf/seaweedfs:4.48`.
- Só executar após aprovação deste plano.

### T1 — Branch e credenciais — → T0
```bash
git checkout -b feat/spec-018-seaweedfs
# gerar 2 pares de chaves (local e EKS), distintos entre si e do MinIO:
openssl rand -hex 10   # accessKey  (x4: local+eks, access+secret com tamanho adequado)
openssl rand -base64 30 | tr -d '/+=' | cut -c1-40   # secretKey
```
Guardar os valores só para colar nos arquivos das T2–T5 (não ecoar em logs/commit message).

### T2 — Application Helm local — → T1
Criar `apps/local/seaweedfs-app.yaml`:
- `repoURL: https://seaweedfs.github.io/seaweedfs/helm`, `chart: seaweedfs`, `targetRevision: 4.48.0`
- `sync-wave: "2"`, `destination.namespace: data-platform`, `CreateNamespace=true`, `automated {prune, selfHeal}`
- values inline:
  ```yaml
  image: { repository: chrislusf/seaweedfs, tag: "4.48" }   # chaves exatas a confirmar com helm template
  master:
    replicas: 1
    data: { type: persistentVolumeClaim, size: 5Gi, storageClass: standard }
    resources: { requests: {cpu: 10m, memory: 64Mi}, limits: {memory: 256Mi} }
  volume:
    replicas: 1
    dataDirs:
      - { name: data1, type: persistentVolumeClaim, size: 20Gi, storageClass: standard, maxVolumes: 0 }
    resources: { requests: {cpu: 20m, memory: 128Mi}, limits: {memory: 512Mi} }
  filer:
    replicas: 1
    data: { type: persistentVolumeClaim, size: 5Gi, storageClass: standard }
    s3: { enabled: false }
    resources: { requests: {cpu: 20m, memory: 128Mi}, limits: {memory: 512Mi} }
  s3:
    enabled: true
    port: 8333
    enableAuth: true
    credentials: { admin: { accessKey: <local>, secretKey: <local> } }
    resources: { requests: {cpu: 10m, memory: 64Mi}, limits: {memory: 256Mi} }
  ```
- Validar o render **antes** de commitar (resolve a única incerteza do spec §4.1/§12):
  ```bash
  python3 -c "import yaml,sys;d=yaml.safe_load(open('apps/local/seaweedfs-app.yaml'));open('/tmp/sw-values.yaml','w').write(d['spec']['source']['helm']['values'])"
  helm template seaweedfs seaweedfs/seaweedfs --version 4.48.0 -n data-platform -f /tmp/sw-values.yaml | grep -E "^kind:|^  name:|image:|storageClassName|storage:"
  ```
  Conferir: 4 workloads (master/volume/filer STS + s3 Deployment), PVCs com a storageClass certa, nome do Secret de credenciais gerado.

### T3 — Application Helm EKS — → T2
Criar `apps/eks/seaweedfs-app.yaml` (cópia de T2) com: `storageClass: gp3`, volume 50Gi, credenciais EKS. Mesmo `helm template` de validação.
Antes: `kubectl --context=data-platform-eks describe nodes | grep -A8 "Allocated resources"` — se os requests alocáveis não comportarem ~0,4Gi, **parar e perguntar** (subir nó vs. reduzir requests; decisão do usuário, spec §4.2).

### T4 — Chart de setup local (buckets) — → T2
Criar `charts/seaweedfs-local-setup/`:
- `kustomization.yaml`: `resources: [create-buckets-job.yaml]` + `configMapGenerator` `seaweedfs-setup-config` (`buckets=bronze warehouse`), `disableNameSuffixHash: true` (idêntico ao `minio-*-setup`)
- `create-buckets-job.yaml`: `Job seaweedfs-create-buckets`, hooks `argocd.argoproj.io/hook: Sync` + `BeforeHookCreation`, `backoffLimit: 20`, `restartPolicy: OnFailure`
  - initContainer `busybox:1.36` → `nc -z seaweedfs-s3.data-platform.svc.cluster.local 8333`
  - container `amazon/aws-cli` (**tag fixa** — o MinIO usa `latest`; aqui fixar, ex. `2.17.x`, definida no Implement) com `--endpoint-url http://seaweedfs-s3.data-platform.svc.cluster.local:8333`, `AWS_DEFAULT_REGION=us-east-1`, credenciais via `secretKeyRef` (ou literal, conforme 2.3)
  - loop `head-bucket || create-bucket` para `bronze warehouse`; ao final `aws s3 ls`
  - **sem** upload do `openmetadata.json` (é do MinIO; não faz parte deste spec)
```bash
kubectl kustomize charts/seaweedfs-local-setup | kubectl apply --dry-run=client -f -
```

### T5 — Chart de setup EKS — → T3, T4
Criar `charts/seaweedfs-eks-setup/` igual a T4 (credenciais EKS). Mesmo dry-run.

### T6 — Applications de setup — → T4, T5
Criar `apps/local/seaweedfs-setup-app.yaml` e `apps/eks/seaweedfs-setup-app.yaml` (modelo: `apps/eks/minio-eks-setup-app.yaml`): `sync-wave: "3"`, `path: charts/seaweedfs-{local,eks}-setup`, `targetRevision: HEAD`, `namespace: data-platform`.
```bash
python3 -c "import yaml,glob;[yaml.safe_load(open(f)) for f in glob.glob('apps/*/seaweedfs*.yaml')];print('yaml ok')"
```

### T7 — Script de verificação — → T4
Criar `scripts/verify-seaweedfs-buckets.sh` (modelo: `scripts/verify-minio-buckets.sh`): lê a lista de `charts/seaweedfs-eks-setup/kustomization.yaml`, sobe pod efêmero `amazon/aws-cli` contra `seaweedfs-s3`, compara com a lista esperada; respeita `KUBE_CONTEXT`; exit 0/1.
```bash
bash -n scripts/verify-seaweedfs-buckets.sh && chmod +x scripts/verify-seaweedfs-buckets.sh
```

### T8 — Integração com Makefile/CI — → T7
- Ler `Makefile` (alvos `verify-eks`, `run-local`) e `.github/workflows/infra-bootstrap.yml`; incluir a chamada de `verify-seaweedfs-buckets.sh` junto de `verify-minio-buckets.sh`.
- Se `wait-argocd-healthy.sh` conta Applications fixas (19), ajustar para +2.
```bash
make -n verify-eks | grep -i seaweed
```

### T9 — Documentação — → T7
- `README.md`: seção SeaweedFS + tabela de endpoints (MinIO × SeaweedFS) + port-forwards (8333, 8888, 9333).
- `docs/runbooks/seaweedfs-setup.md`: operação, `aws --endpoint-url`, troubleshooting, **aviso de que os dois storages têm buckets com o mesmo nome**.
- `CLAUDE.md`: reescrever a decisão "Storage do lakehouse" (MinIO e SeaweedFS coexistem; SeaweedFS é o destino final). **Status só após `/validate-spec`.**

### T10 — Commit, PR e rollout — → T2–T9
```bash
git add apps/local/seaweedfs*.yaml apps/eks/seaweedfs*.yaml charts/seaweedfs-*-setup scripts/verify-seaweedfs-buckets.sh docs README.md CLAUDE.md Makefile specs
git commit        # com a linha Co-Authored-By exigida
git push -u origin feat/spec-018-seaweedfs
```
O `app-of-apps` (local e EKS) rastreia a branch **`main`** e o setup usa `HEAD`: os Apps só aparecem depois do merge. Sequência:
1. PR → revisão → merge em `main`
2. **Local primeiro:** `make run-local` (ou sync do app-of-apps) → critérios do spec em kind
3. **EKS depois:** o app-of-apps sincroniza sozinho (ou `argocd app sync app-of-apps`); acompanhar `kubectl --context=data-platform-eks get applications -n argocd -w`
Sem `kubectl apply` manual (regra do CLAUDE.md).

## 4. Riscos identificados
| Risco | Mitigação |
|---|---|
| Rollout só testável após merge em `main` (app-of-apps/HEAD) | Pré-merge: `helm template` + `kubectl kustomize … --dry-run`; pós-merge: local antes de EKS; falha do SeaweedFS não bloqueia o resto (wave isolada, nada depende dele) |
| Memória do EKS em 63–76% | Conferir requests alocáveis antes do sync (T3); requests mínimos; se não couber, parar e perguntar |
| Chaves de `values` divergirem (chart 4.x mudou muito: `image.*`, `s3.credentials`, `master.data`) | `helm template` obrigatório em T2/T3; ajustar até renderizar PVCs/imagem/Secret esperados |
| Imagem `chrislusf/seaweedfs:4.48` (Docker Hub): rate limit/política | Tag fixa; se `ImagePullBackOff`, abrir spec de espelho no ECR |
| Credencial estática versionada | Aceito (decisão 4); chaves novas, distintas das do MinIO; nunca reutilizar chaves do MinIO |
| Mesmo nome de bucket nos dois storages → escrita no lugar errado | Credenciais e DNS distintos; runbook com tabela de endpoints |
| PVC `Pending` (kind sem `standard` / EKS gp3 `WaitForFirstConsumer`) | `kubectl get sc` antes; `describe pvc` se travar |
| Perda do filer (leveldb) | Aceito agora (sem dado de produção); backup antes da 1ª migração de dados |
| Job de buckets antes do S3 pronto | initContainer + `backoffLimit: 20` (padrão já provado no MinIO) |

## 5. Comandos de validação básica (rodados pelo Implement ao fim de cada tarefa)
| Tarefa | Comando |
|---|---|
| T0 | `grep -n "Decisões em aberto" specs/SPEC-018-SeaweedFS.md` e revisão visual do diff |
| T2/T3 | `helm template seaweedfs seaweedfs/seaweedfs --version 4.48.0 -n data-platform -f /tmp/sw-values.yaml \| grep -E "kind:\|image:\|storageClassName"` — esperar STS master/volume/filer + Deployment s3, imagem `chrislusf/seaweedfs:4.48` |
| T4/T5 | `kubectl kustomize charts/seaweedfs-{local,eks}-setup \| kubectl apply --dry-run=client -f -` |
| T6 | `python3 -c "…safe_load…"` em `apps/*/seaweedfs*.yaml`; `grep sync-wave apps/*/seaweedfs*.yaml` (2 e 3) |
| T7 | `bash -n scripts/verify-seaweedfs-buckets.sh` |
| T8 | `make -n verify-eks` |
| T10 (pós-merge, local) | `kubectl get app seaweedfs seaweedfs-setup -n argocd`; `kubectl get pods,pvc -n data-platform \| grep -i seaweed`; `bash scripts/verify-seaweedfs-buckets.sh` |
| T10 (pós-merge, EKS) | idem com `--context=data-platform-eks`; `bash scripts/verify-minio-buckets.sh` (coexistência); `kubectl --context=data-platform-eks get applications -n argocd \| grep -vc "Synced.*Healthy"` = 0 |

> A validação formal (12 critérios do spec §6) fica para `/validate-spec SPEC-018-SeaweedFS`, em subagent de contexto limpo.

## 6. Pontos que preciso que você aprove
1. As alterações no spec da seção 2.3 (credenciais estáticas)
2. Se o Job lê as credenciais do Secret gerado pelo chart (recomendado) ou usa literal próprio como no MinIO
3. As decisões 5 e 6 (seção 2.2)
4. O fluxo de rollout via merge em `main` (T10)
