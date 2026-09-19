#!/bin/bash
# Script para configurar o banco de dados do Iceberg JDBC Catalog
# Executar após o PostgreSQL do Hive Metastore estar rodando

set -e

POSTGRES_POD="hive-metastore-postgres-0"
NAMESPACE="data-platform"
DB_USER="hive"
DB_PASSWORD="hive123"

echo "Creating iceberg_catalog database..."
kubectl exec $POSTGRES_POD -n $NAMESPACE -- bash -c "PGPASSWORD=$DB_PASSWORD psql -U $DB_USER -d metastore -c 'CREATE DATABASE iceberg_catalog OWNER hive;'" 2>/dev/null || echo "Database already exists"

echo "Granting privileges..."
kubectl exec $POSTGRES_POD -n $NAMESPACE -- bash -c "PGPASSWORD=$DB_PASSWORD psql -U $DB_USER -d iceberg_catalog -c '
GRANT ALL PRIVILEGES ON DATABASE iceberg_catalog TO hive;
GRANT ALL PRIVILEGES ON SCHEMA public TO hive;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO hive;
'"

echo "Creating Iceberg catalog tables..."
kubectl exec $POSTGRES_POD -n $NAMESPACE -- bash -c "PGPASSWORD=$DB_PASSWORD psql -U $DB_USER -d iceberg_catalog -c '
CREATE TABLE IF NOT EXISTS iceberg_tables (
    catalog_name VARCHAR(255) NOT NULL,
    table_namespace VARCHAR(255) NOT NULL,
    table_name VARCHAR(255) NOT NULL,
    metadata_location VARCHAR(1000),
    previous_metadata_location VARCHAR(1000),
    PRIMARY KEY (catalog_name, table_namespace, table_name)
);

CREATE TABLE IF NOT EXISTS iceberg_namespace_properties (
    catalog_name VARCHAR(255) NOT NULL,
    namespace VARCHAR(255) NOT NULL,
    property_key VARCHAR(255) NOT NULL,
    property_value VARCHAR(1000),
    PRIMARY KEY (catalog_name, namespace, property_key)
);
'"

echo "JDBC Catalog setup complete!"
