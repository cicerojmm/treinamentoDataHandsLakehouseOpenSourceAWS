import duckdb
import boto3
from botocore.config import Config

from app.config import MINIO_ENDPOINT, MINIO_ACCESS_KEY, MINIO_SECRET_KEY, MINIO_BUCKET, ICEBERG_SCHEMA


def get_connection() -> duckdb.DuckDBPyConnection:
    conn = duckdb.connect(":memory:")
    conn.execute("INSTALL iceberg; LOAD iceberg;")
    conn.execute("INSTALL httpfs; LOAD httpfs;")
    conn.execute(f"""
        SET s3_endpoint = '{MINIO_ENDPOINT}';
        SET s3_access_key_id = '{MINIO_ACCESS_KEY}';
        SET s3_secret_access_key = '{MINIO_SECRET_KEY}';
        SET s3_use_ssl = false;
        SET s3_url_style = 'path';
        SET unsafe_enable_version_guessing = true;
    """)
    return conn


def get_s3_client():
    return boto3.client(
        "s3",
        endpoint_url=f"http://{MINIO_ENDPOINT}",
        aws_access_key_id=MINIO_ACCESS_KEY,
        aws_secret_access_key=MINIO_SECRET_KEY,
        config=Config(signature_version="s3v4"),
        region_name="us-east-1",
    )


def find_iceberg_table_path(table_name: str, schema: str = None) -> str:
    # Sem cache: o dbt troca o diretorio fisico da tabela a cada run
    # (materializacao "table" cria um <nome>__dbt_tmp-<uuid> novo e faz
    # o swap no catalogo). Um path cacheado do processo fica orfao no
    # primeiro run seguinte e o iceberg_scan passa a falhar (nao acha
    # mais metadata.json ali). Relistar a cada chamada custa uma
    # list_objects_v2, barato frente ao problema que evita.
    schema = schema or ICEBERG_SCHEMA
    s3 = get_s3_client()
    prefix = f"{schema}/{table_name}"

    response = s3.list_objects_v2(Bucket=MINIO_BUCKET, Prefix=prefix, Delimiter="/")

    for obj in response.get("CommonPrefixes", []):
        dir_name = obj["Prefix"].rstrip("/")
        if dir_name.startswith(prefix):
            return f"s3://{MINIO_BUCKET}/{dir_name}"

    return f"s3://{MINIO_BUCKET}/{prefix}"


def query_iceberg(table_name: str, query_suffix: str = "", schema: str = None) -> list[dict]:
    conn = get_connection()
    path = find_iceberg_table_path(table_name, schema)
    sql = f"SELECT * FROM iceberg_scan('{path}') {query_suffix}"
    result = conn.execute(sql).fetchdf()
    conn.close()
    # NULL numerico vira NaN no pandas, que o JSON padrao rejeita (500).
    result = result.astype(object).where(result.notna(), None)
    return result.to_dict(orient="records")
