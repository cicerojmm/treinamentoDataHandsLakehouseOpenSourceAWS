# Plano de Implementação: SPEC-016 (CI/CD)

## Pré-requisitos verificados
- SPEC-002 (ECR): concluído — 5 repositórios já existem em `data-platform/*`.
- SPEC-015 (overlays EKS): concluído, validado 2026-09-23 (5/5 critérios).
- `terraform` local v1.14.1 (satisfaz `>= 1.10` exigido pelo backend S3 com `use_lockfile`).
- Bucket `cjmm-datahandson-configs` existe (região `us-east-1`), SSE-S3 ligado, acesso público bloqueado, sem versionamento (decisão: não mexer). Já usado por outro projeto (`terraform/data_handson_dq/terraform.tfstate`).
- `gh` CLI **não está instalado** localmente — os passos de Secrets usam a UI do GitHub (ou instalar o CLI antes, fora deste plano).

## Decisões do usuário incorporadas nesta revisão (segunda rodada: sem migração em lugar nenhum)
1. **Nem `envs/eks` nem `envs/shared` migram state.** Os dois ambientes atuais foram destruídos e recriados do zero, com backend S3 desde o primeiro `terraform init`. Nada de `-migrate-state`.
2. **`envs/shared` (ECR) — já executado nesta sessão:**
   - Os 5 repositórios ECR (`airflow-dags`, `dbt-project`, `api-service`, `spark-jobs`, `metabase`) foram apagados via `aws ecr delete-repository --force` (41 imagens perdidas, decisão explícita do usuário).
   - `infra/terraform/envs/shared/backend.tf` criado, `required_version` bumpado para `>= 1.10`, `"metabase"` adicionado a `ecr_repositories` (não precisa mais de `terraform import` — não existe nada pra importar, é criação nova junto com os outros 4).
   - `terraform init` limpo (sem prompt de migração, confirmando que não havia state a copiar) + `terraform apply`: `10 added, 0 changed, 0 destroyed` (5 repos + 5 lifecycle policies). State confirmado em `s3://cjmm-datahandson-configs/terraform/lakehouse_opensource_eks/shared/terraform.tfstate`.
   - Efeito colateral notado: o `metabase` era `MUTABLE` (criado à mão antes); agora é `IMMUTABLE` como os outros, consistente com a decisão "tag = SHA, nunca sobrescreve".
3. **`envs/eks`:** o usuário rodou o `terraform destroy` por conta própria (`make destroy-eks`), em paralelo a esta sessão. Falta: `backend.tf` + bump de `required_version` + `terraform init` limpo, feito **depois** que o destroy terminar (não durante — evitar mexer nos arquivos de um diretório com um `terraform` em execução).
4. **Makefile continua funcional** para uso manual sem CI/CD — nenhuma tarefa deste plano muda a assinatura de `build.sh` nem o comportamento de `make images-eks`/`make bootstrap-eks`. Como o ECR está vazio agora, o próximo `make bootstrap-eks` (se rodado antes do CI/CD existir) vai rebuildar as 3 imagens do zero via `ensure-images-eks.sh` — comportamento normal do script, não é regressão.
5. **Sem usuário IAM dedicado agora.** GitHub Secrets recebem as credenciais root já usadas localmente. Risco aceito e registrado no spec. Nenhum recurso IAM novo é criado — o antigo Grupo B (`iam-github.tf`, `create-access-key`) foi eliminado do plano.
6. **Profile do `dbt parse`:** confirmado localmente — `dbt deps` + `dbt parse` rodam com exit 0 sem nenhuma env var extra (`code/dbt-project/profiles/profiles.yml` já tem defaults em todo `env_var()`).

## Tarefas

### Grupo A — Backend S3 do Terraform

**1-2. `envs/shared`: CONCLUÍDO nesta sessão.** ECR apagado e recriado do zero (5 repos + lifecycle policies), backend S3 configurado, state confirmado em `s3://cjmm-datahandson-configs/terraform/lakehouse_opensource_eks/shared/terraform.tfstate`. Ver "Decisões incorporadas" item 2 acima para o detalhe do que rodou.

**3. `infra/terraform/envs/eks/backend.tf`** (novo, ainda pendente) — mesma estrutura do `envs/shared`, trocando a key:
```hcl
terraform {
  backend "s3" {
    bucket       = "cjmm-datahandson-configs"
    key          = "terraform/lakehouse_opensource_eks/eks/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
```
Editar `infra/terraform/envs/eks/providers.tf` linha 2: `required_version = ">= 1.5.0"` → `">= 1.10"`.

**4. Sem migração para `envs/eks`.** Pré-condição: `terraform destroy` do ambiente atual **totalmente concluído** (rodando em paralelo a este plano — não mexer nos arquivos do diretório enquanto o processo estiver ativo). Depois disso:
```bash
cd infra/terraform/envs/eks
rm -f terraform.tfstate terraform.tfstate.backup   # local, pos-destroy, vazio
terraform init   # sem -migrate-state; cria o state novo direto no S3
```
Não é bloqueante para os grupos C/D/E/F — só bloqueia o primeiro `terraform apply`/`make bootstrap-eks` real do ambiente novo.

### Grupo B — (eliminado)
Existia só para importar o `metabase` no Terraform sem recriar do zero. Como `envs/shared` inteiro foi recriado do zero (decisão do usuário), o `metabase` já nasceu gerenciado junto com os outros 4 — não há mais nada pra importar.

### Grupo C — Credenciais no GitHub (manual, do usuário) — PENDENTE

**7. GitHub Secrets** `AWS_ACCESS_KEY_ID` e `AWS_SECRET_ACCESS_KEY` — o usuário copia da própria credencial local (`aws configure get aws_access_key_id`/`aws_secret_access_key`) direto para Settings → Secrets and variables → Actions do repositório. Eu não leio nem imprimo esses valores. Passo a passo em `docs/runbooks/cicd-setup.md` (tarefa 21, concluída).

**Dependência:** nenhuma — pode ser feita a qualquer momento, mas é pré-requisito para qualquer workflow (Grupo F) rodar de verdade (login no ECR falha sem isso).

### Grupo D — Build da `airflow-dags` a partir da raiz — CONCLUÍDO

**8. `.dockerignore`** (novo, raiz do repo):
```
.git
.terraform
*.tfstate*
infra/
docs/
specs/
.claude/
```

**9. `code/airflow-dags/Dockerfile`** — trocar paths para contexto = raiz:
```dockerfile
COPY code/airflow-dags/requirements.txt /tmp/requirements.txt
...
COPY --chown=airflow:root code/airflow-dags/dags/ /opt/airflow/dags/
COPY --chown=airflow:root code/dbt-project/ /opt/airflow/dbt/movielens/
```

**10. `code/airflow-dags/build.sh`** — sem a cópia manual de `dbt-project`, builda direto da raiz, **mesma assinatura** (`build.sh <tag>`):
```bash
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
TAG=${1:-"latest"}
REPO="093499160510.dkr.ecr.us-east-2.amazonaws.com/data-platform/airflow-dags"
docker build -f "$SCRIPT_DIR/Dockerfile" -t "$REPO:$TAG" "$PROJECT_ROOT"
echo "Done! Image: $REPO:$TAG"
```
`scripts/ensure-images-eks.sh` e `make images-eks`/`make bootstrap-eks` continuam funcionando sem alteração (mesma assinatura de `build.sh`).

**11. Validar: CONCLUÍDO.** `bash code/airflow-dags/build.sh test-root-build` da raiz do repo buildou com sucesso; import das DAGs (tarefa 16) confirmado contra a imagem, 33 tasks, sem erro. Imagem de teste removida depois.

**Dependência:** 8→9→10→11. Independente dos grupos A/B/C.

### Grupo E — Testes (portão antes do build) — CONCLUÍDO
`pytest code/api-service/tests/ -v`: 4/4 passou. `dbt parse`: exit 0. Precisou de um `code/api-service/pytest.ini` (`pythonpath = .`) não previsto no plano original, pra `from app.main import app` resolver fora de um `pip install -e`.

**12. `.gitignore`** (raiz ou `code/dbt-project/`): adicionar `profiles/.user.yml` (arquivo de telemetria que o `dbt parse` cria — observado ao testar localmente hoje).

**13. `code/api-service/app/db.py`** — extrair a limpeza de NaN pra uma função pura, testável sem MinIO/DuckDB:
```python
def _records_from_df(df) -> list[dict]:
    df = df.astype(object).where(df.notna(), None)
    return df.to_dict(orient="records")
```
`query_iceberg` passa a chamar essa função no lugar das duas linhas atuais.

**14. `code/api-service/requirements-dev.txt`** (novo): `pytest`, `httpx`.

**15. `code/api-service/tests/test_api.py`** (novo) — confirmado que `app/config.py`/`app/main.py` não fazem I/O na importação, roda 100% offline:
```python
import pandas as pd
from fastapi.testclient import TestClient
from app.main import app
from app.db import _records_from_df

client = TestClient(app)

def test_health():
    assert client.get("/health").status_code == 200

def test_sem_api_key_401():
    assert client.get("/api/v1/movies").status_code == 401

def test_api_key_errada_401():
    assert client.get("/api/v1/movies", headers={"X-API-Key": "errada"}).status_code == 401

def test_nan_vira_null():
    df = pd.DataFrame({"a": [1, 2], "b": [1.5, float("nan")]})
    records = _records_from_df(df)
    assert records[1]["b"] is None
```

**16. Teste de import das DAGs** (step do workflow, não é arquivo do repo) — validado nesta sessão contra a imagem real, com 2 correções que o plano original não previa:
- `DagBag(dag_folder=...)` **sem** `include_examples` — esse kwarg não existe mais no Airflow 3.3.0 (`TypeError: unexpected keyword argument`).
- `AIRFLOW__COSMOS__ENABLE_CACHE=False` como env var do container — sem isso, o `DbtTaskGroup` do Cosmos tenta **gravar** um cache de parsing como Airflow Variable no banco de metadados durante o próprio parse da DAG (não é só leitura), e quebra com `sqlite3.OperationalError: no such table: variable` porque não há banco migrado no container standalone.
```bash
docker run --rm -e AIRFLOW__COSMOS__ENABLE_CACHE=False <imagem> python -c "
from airflow.models import DagBag
db = DagBag(dag_folder='/opt/airflow/dags')
assert not db.import_errors, db.import_errors
assert 'dbt_movielens' in db.dags
"
```
Testado: 2 dags, `dbt_movielens` com 33 tasks, sem erro de import.

**Dependência:** 13 antes de 15. Resto independente. Independente dos outros grupos.

### Grupo F — Workflows do GitHub Actions — ESCRITOS, validados com `actionlint` (0 problemas); execução real pendente dos Secrets (Grupo C)

**17. `.github/workflows/_build-push-bump.yml`** — CONCLUÍDO, com uma correção de desenho em relação ao plano original: os testes viraram **`pre-build-test-command`** (roda no runner, antes do `docker build`) e **`post-build-test-command`** (roda com `docker run` contra a imagem recém-buildada, antes do `docker push`) — o teste de import das DAGs (tarefa 16) só existe depois que a imagem é montada, não dá pra rodar "antes do build" como o plano original supunha. A imagem só é publicada (`docker push`) depois dos dois passarem, então o critério de aceite 5 (teste quebrado não publica nada) continua valendo.

**18. `.github/workflows/airflow-dags.yml`** — CONCLUÍDO. `paths: [code/airflow-dags/**, code/dbt-project/**]`. Pre-build: `dbt deps` + `dbt parse`. Post-build: import das DAGs com `AIRFLOW__COSMOS__ENABLE_CACHE=False` (achado da tarefa 16). Bump dos **dois** campos do `apps/eks/airflow-app.yaml` (`tag:` e `worker_container_tag:`) no mesmo commit, via `sed` ancorado no nome da chave (idempotente, funciona em qualquer formato de tag anterior).

**19. `.github/workflows/api-service.yml`** — CONCLUÍDO. Correção de sintaxe: GitHub Actions não permite `paths` + `paths-ignore` juntos no mesmo gatilho (erro de validação da própria plataforma) — usei `!code/api-service/k8s-eks/**` dentro da mesma lista `paths`, que é a forma suportada de excluir um path. Pre-build: pytest (tarefa 15). Bump do `kustomization.yaml`.

**20. `.github/workflows/metabase.yml`** — CONCLUÍDO. `paths: [code/metabase/**]`, sem testes de código próprio. Bump do `charts/metabase-eks/metabase.yaml`.

### Grupo G — Documentação — CONCLUÍDO

**21. `docs/runbooks/cicd-setup.md`** — criado: como pegar a credencial local e configurar os Secrets, como testar com `workflow_dispatch`, rollback, nota sobre o risco de credenciais root.

**22. `specs/SPEC-016-cicd.md`** — `Status:` já atualizado para `Plan aprovado, Implement em andamento` no início desta fase.

## Pendências para fechar o Implement
1. **Grupo C (usuário):** configurar `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` nos GitHub Secrets — sem isso nenhum workflow consegue logar no ECR.
2. **Prova end-to-end real:** depois dos Secrets configurados, disparar um `workflow_dispatch` (ou um push de teste) pra confirmar build→push→bump→(ArgoCD sync, quando o cluster existir) na prática — o que só é testável de fato depois que os Secrets existirem e, para o passo do ArgoCD, depois que o `envs/eks` for recriado (decisão do usuário: "depois criamos o ambiente pelo CI/CD").
3. **`terraform apply` do `envs/eks`** (recriar o cluster) — deliberadamente adiado pelo usuário para depois do CI/CD estar pronto, não é um item quebrado do plano.

## Riscos identificados
- **Credenciais root nos GitHub Secrets:** qualquer vazamento (log acidental, dependência de Action comprometida, injeção num step) dá controle total da conta AWS, não só do ECR. Risco aceito pelo usuário; mitigação futura é o IAM dedicado (fora de escopo aqui).
- **41 imagens ECR perdidas permanentemente** (executado): sem rollback possível para builds anteriores a hoje. Aceito pelo usuário — próximos builds (manuais ou via CI/CD) começam do zero.
- **`envs/eks` sem migração depende do `terraform destroy` em andamento terminar por completo** antes da tarefa 4. Rodar `terraform init` sem `-migrate-state` enquanto ainda existem recursos reais não gerenciados por esse state não é destrutivo por si só (não faz `apply`), mas confunde o próximo `plan`. Mitigar: só rodar a tarefa 4 depois de confirmar `aws eks list-clusters` vazio.
- **`.dockerignore` na raiz** pode afetar builds de `code/api-service`/`code/metabase` se algum precisar de arquivo fora do próprio diretório — nenhum precisa hoje; checar ao escrever as tarefas 19-20.
- **Corrida entre workflows:** dois merges quase simultâneos no mesmo componente — cobertos por `concurrency` + retry com rebase (tarefa 17). Componentes diferentes não colidem (manifestos diferentes).

## Comandos de validação básica (fim de cada tarefa, não é o `/validate-spec` formal)
- Grupo A: `envs/shared` — já confirmado (`terraform plan` limpo, `aws ecr get-lifecycle-policy --repository-name data-platform/metabase` responde). `envs/eks` — `terraform state list` funcionando (mesmo que vazio, recém criado).
- Grupo D: `docker run --rm <imagem> airflow dags list-import-errors` vazio.
- Grupo E: `pytest code/api-service/tests/ -v` com 4/4 passando; `dbt parse --project-dir code/dbt-project --profiles-dir code/dbt-project/profiles` exit 0.
- Grupo F: push de teste num branch + PR, merge, conferir no GitHub Actions que só o workflow certo disparou e que o commit de bump apareceu no `main`.
- Fim a fim: `make images-eks` e `make bootstrap-eks` continuam funcionando sem nenhuma mudança de uso (valida a decisão do usuário de manter o Makefile).
