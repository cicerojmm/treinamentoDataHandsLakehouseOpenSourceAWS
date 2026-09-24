# validacao SPEC-016: push de teste do CI (revertido em seguida)
from fastapi import FastAPI

from app.routers import movies

app = FastAPI(
    title="Lakehouse API",
    description="API de exemplo consumindo dados Iceberg do MinIO via DuckDB",
    version="1.0.0",
)

app.include_router(movies.router)


@app.get("/health")
async def health():
    """Health check endpoint (sem autenticação)."""
    return {"status": "healthy"}


@app.get("/ready")
async def ready():
    """Readiness check endpoint (sem autenticação)."""
    return {"status": "ready"}
