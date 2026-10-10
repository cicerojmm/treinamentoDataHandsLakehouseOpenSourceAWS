"""
DAG que consulta a cotacao USD-BRL dos ultimos 15 dias (AwesomeAPI, publica)
e grava o JSON cru em s3://bronze/dados_dolar/.
"""
from datetime import datetime, timedelta
import json

import requests
from airflow.decorators import dag, task
from airflow.providers.amazon.aws.hooks.s3 import S3Hook

API_URL = "https://economia.awesomeapi.com.br/json/daily/USD-BRL/15"
BUCKET = "bronze"
PREFIX = "dados_dolar"
MINIO_CONN_ID = "minio_bronze"


@dag(
    dag_id="dolar_bronze",
    schedule="@daily",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    default_args={
        "retries": 2,
        "retry_delay": timedelta(minutes=2),
        "retry_exponential_backoff": True,
    },
    tags=["bronze", "dolar"],
)
def dolar_bronze():
    @task
    def fetch_cotacao_dolar() -> list[dict]:
        resp = requests.get(API_URL, timeout=30)
        resp.raise_for_status()
        cotacoes = resp.json()
        if not cotacoes:
            raise ValueError("API retornou lista vazia")
        return cotacoes

    @task
    def upload_to_bronze(cotacoes: list[dict], ds=None) -> str:
        key = f"{PREFIX}/cotacao_dolar_{ds}.json"
        S3Hook(aws_conn_id=MINIO_CONN_ID).load_string(
            string_data=json.dumps(cotacoes, ensure_ascii=False),
            key=key,
            bucket_name=BUCKET,
            replace=True,
        )
        return f"s3://{BUCKET}/{key}"

    upload_to_bronze(fetch_cotacao_dolar())


dolar_bronze()
