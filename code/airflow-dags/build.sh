#!/bin/bash
# Build script for Airflow DAGs image. Contexto = raiz do repo (o
# Dockerfile copia code/airflow-dags/dags e code/dbt-project de la).
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

TAG=${1:-"latest"}
REPO="093499160510.dkr.ecr.us-east-2.amazonaws.com/data-platform/airflow-dags"

echo "Building Docker image..."
docker build -f "$SCRIPT_DIR/Dockerfile" -t "$REPO:$TAG" "$PROJECT_ROOT"

echo "Done! Image: $REPO:$TAG"
