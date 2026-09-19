#!/bin/bash
# Script to configure Airbyte to use existing MinIO instead of internal MinIO

set -e

echo "=== Creating airbyte-storage bucket in existing MinIO ==="
kubectl exec -n data-platform minio-local-pool-0-0 -c minio -- mc alias set local http://localhost:9000 minio minio123
kubectl exec -n data-platform minio-local-pool-0-0 -c minio -- mc mb local/airbyte-storage --ignore-existing

echo ""
echo "=== Patching Airbyte ConfigMap to use existing MinIO ==="
kubectl patch cm airbyte-airbyte-env -n ingestion --type='json' -p='[
  {"op": "replace", "path": "/data/MINIO_ENDPOINT", "value": "http://minio-local-hl.data-platform.svc.cluster.local:9000"},
  {"op": "replace", "path": "/data/AWS_ACCESS_KEY_ID", "value": "minio"},
  {"op": "replace", "path": "/data/AWS_SECRET_ACCESS_KEY", "value": "minio123"}
]'

echo ""
echo "=== Scaling down internal Airbyte MinIO ==="
kubectl scale statefulset airbyte-minio -n ingestion --replicas=0

echo ""
echo "=== Restarting Airbyte deployments ==="
kubectl rollout restart deployment -n ingestion

echo ""
echo "=== Done! Airbyte now uses existing MinIO at minio-local-hl.data-platform.svc.cluster.local:9000 ==="
