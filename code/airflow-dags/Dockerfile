FROM apache/airflow:3.3.0-python3.11

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    git \
    && rm -rf /var/lib/apt/lists/*

USER airflow

# Contexto de build = raiz do repo (make images-eks, CI/CD e
# code/airflow-dags/build.sh rodam da raiz).
COPY code/airflow-dags/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

RUN pip install --no-cache-dir \
    "astronomer-cosmos[dbt-trino]>=1.5.0" \
    "dbt-trino>=1.9,<1.10"

COPY --chown=airflow:root code/airflow-dags/dags/ /opt/airflow/dags/
COPY --chown=airflow:root code/dbt-project/ /opt/airflow/dbt/movielens/
