"""
DAG para processar dados Movielens: cria external tables na bronze e executa dbt.
Fluxo: Bronze (Parquet) -> Staging (Iceberg) -> Silver (Iceberg) -> Gold (Iceberg)
"""
from datetime import datetime

from airflow import DAG
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator
from cosmos import DbtTaskGroup, ProjectConfig, ProfileConfig, ExecutionConfig


CREATE_BRONZE_SCHEMA_SQL = "CREATE SCHEMA IF NOT EXISTS hive_bronze.movielens"

CREATE_MOVIES_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS hive_bronze.movielens.movies (
    movieid BIGINT,
    title VARCHAR,
    genres VARCHAR
) WITH (
    external_location = 's3://bronze/movielens/movies/',
    format = 'PARQUET'
)
"""

CREATE_RATINGS_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS hive_bronze.movielens.ratings (
    userid BIGINT,
    movieid BIGINT,
    rating DOUBLE,
    timestamp BIGINT
) WITH (
    external_location = 's3://bronze/movielens/ratings/',
    format = 'PARQUET'
)
"""

CREATE_LINKS_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS hive_bronze.movielens.links (
    movieid BIGINT,
    imdbid VARCHAR,
    tmdbid VARCHAR
) WITH (
    external_location = 's3://bronze/movielens/links/',
    format = 'PARQUET'
)
"""

CREATE_TAGS_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS hive_bronze.movielens.tags (
    userid BIGINT,
    movieid BIGINT,
    tag VARCHAR,
    timestamp BIGINT
) WITH (
    external_location = 's3://bronze/movielens/tags/',
    format = 'PARQUET'
)
"""


default_args = {
    "owner": "data-platform",
    "retries": 1,
}

with DAG(
    dag_id="dbt_movielens",
    description="Processa dados Movielens: Bronze (Parquet) -> Staging -> Silver -> Gold (Iceberg)",
    schedule=None,
    start_date=datetime(2024, 1, 1),
    catchup=False,
    default_args=default_args,
    tags=["dbt", "movielens", "lakehouse"],
) as dag:

    create_schema = SQLExecuteQueryOperator(
        task_id="create_bronze_schema",
        conn_id="trino_default",
        sql=CREATE_BRONZE_SCHEMA_SQL,
        handler=list,
    )

    create_movies = SQLExecuteQueryOperator(
        task_id="create_movies_table",
        conn_id="trino_default",
        sql=CREATE_MOVIES_TABLE_SQL,
        handler=list,
    )

    create_ratings = SQLExecuteQueryOperator(
        task_id="create_ratings_table",
        conn_id="trino_default",
        sql=CREATE_RATINGS_TABLE_SQL,
        handler=list,
    )

    create_links = SQLExecuteQueryOperator(
        task_id="create_links_table",
        conn_id="trino_default",
        sql=CREATE_LINKS_TABLE_SQL,
        handler=list,
    )

    create_tags = SQLExecuteQueryOperator(
        task_id="create_tags_table",
        conn_id="trino_default",
        sql=CREATE_TAGS_TABLE_SQL,
        handler=list,
    )

    dbt_transform = DbtTaskGroup(
        group_id="dbt_transform",
        project_config=ProjectConfig(
            dbt_project_path="/opt/airflow/dbt/movielens",
        ),
        profile_config=ProfileConfig(
            profile_name="movielens",
            target_name="local",
            profiles_yml_filepath="/opt/airflow/dbt/movielens/profiles/profiles.yml",
        ),
        execution_config=ExecutionConfig(
            dbt_executable_path="/usr/local/bin/dbt",
        ),
        default_args=default_args,
    )

    create_schema >> [create_movies, create_ratings, create_links, create_tags] >> dbt_transform
