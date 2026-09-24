from datetime import datetime, timedelta

from airflow import DAG
from airflow.providers.standard.operators.bash import BashOperator

default_args = {
    "owner": "data-platform",
    "depends_on_past": False,
    "email_on_failure": False,
    "email_on_retry": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=5),
}

with DAG(
    dag_id="hello_world_dag",
    default_args=default_args,
    description="DAG de exemplo simples, usada para testar o pipeline de CI/CD de DAGs",
    schedule=None,
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["example"],
) as dag:

    hello_task = BashOperator(
        task_id="hello",
        bash_command='echo "Hello from hello_world_dag! $(date)"',
    )
