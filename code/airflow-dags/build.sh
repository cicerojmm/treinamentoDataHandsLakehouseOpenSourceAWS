#!/bin/bash
# Build script for Airflow DAGs image
# This script copies the dbt project into the build context before building

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Copy dbt-project to build context
echo "Copying dbt-project to build context..."
rm -rf "$SCRIPT_DIR/dbt-project"
cp -r "$PROJECT_ROOT/code/dbt-project" "$SCRIPT_DIR/dbt-project"

# Build the image
echo "Building Docker image..."
TAG=${1:-"latest"}
REPO="093499160510.dkr.ecr.us-east-2.amazonaws.com/data-platform/airflow-dags"

docker build -t "$REPO:$TAG" "$SCRIPT_DIR"

# Cleanup
echo "Cleaning up..."
rm -rf "$SCRIPT_DIR/dbt-project"

echo "Done! Image: $REPO:$TAG"
