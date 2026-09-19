# Apps Local

Este diretório contém as Applications do ArgoCD para o ambiente local.

O ArgoCD monitora este diretório via `app-of-apps` e sincroniza automaticamente
qualquer arquivo `.yaml` que defina uma Application válida.

## Estrutura esperada

Cada componente da plataforma terá seu próprio arquivo aqui:
- `minio.yaml` (SPEC-003)
- `hive-metastore.yaml` (SPEC-004)
- `airflow.yaml` (SPEC-005)
- etc.

## Notas

- `selfHeal: true` está ativo — mudanças manuais no cluster serão revertidas
- Sempre faça alterações via Git, nunca diretamente no cluster
