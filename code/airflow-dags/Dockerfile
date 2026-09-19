FROM apache/airflow:3.3.0-python3.11

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    git \
    && rm -rf /var/lib/apt/lists/*

USER airflow

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

RUN pip install --no-cache-dir \
    "astronomer-cosmos[dbt-trino]>=1.5.0" \
    "dbt-trino>=1.9,<1.10"

COPY --chown=airflow:root dags/ /opt/airflow/dags/

# dbt project - copiado de code/dbt-project durante o build
COPY --chown=airflow:root dbt-project/ /opt/airflow/dbt/movielens/
