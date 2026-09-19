import os

MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT", "minio-local-hl.data-platform.svc.cluster.local:9000")
MINIO_ACCESS_KEY = os.getenv("MINIO_ACCESS_KEY", "minio")
MINIO_SECRET_KEY = os.getenv("MINIO_SECRET_KEY", "minio123")
MINIO_BUCKET = os.getenv("MINIO_BUCKET", "warehouse")
ICEBERG_SCHEMA = os.getenv("ICEBERG_SCHEMA", "gold")

API_KEY = os.getenv("API_KEY", "changeme")
