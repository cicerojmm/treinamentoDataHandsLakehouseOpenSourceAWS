from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.providers.cncf.kubernetes.operators.pod import KubernetesPodOperator

default_args = {
    "owner": "data-platform",
    "depends_on_past": False,
    "email_on_failure": False,
    "email_on_retry": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}

with DAG(
    dag_id="example_healthcheck_dag",
    default_args=default_args,
    description="DAG de healthcheck para validar o Airflow e KubernetesExecutor",
    schedule=None,
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["healthcheck", "example"],
) as dag:

    bash_task = BashOperator(
        task_id="bash_healthcheck",
        bash_command='echo "Airflow scheduler está funcionando! $(date)"',
    )

    k8s_task = KubernetesPodOperator(
        task_id="k8s_pod_healthcheck",
        name="healthcheck-pod",
        namespace="orchestration",
        image="busybox:1.36",
        cmds=["sh", "-c"],
        arguments=["echo 'KubernetesExecutor funcionando!' && date"],
        get_logs=True,
        is_delete_operator_pod=True,
        in_cluster=True,
    )

    bash_task >> k8s_task
