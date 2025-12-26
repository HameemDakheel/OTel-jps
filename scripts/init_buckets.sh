#!/bin/bash
# =============================================================================
# MinIO Bucket Initialization Script
# =============================================================================
# Creates required buckets for LGTM+P stack
# Run this after MinIO is healthy
# =============================================================================

set -e

MINIO_HOST="${MINIO_HOST:-minio:9000}"
MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-minioadmin}"
MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-minioadmin123}"

echo "Waiting for MinIO to be ready..."
until curl -sf "http://${MINIO_HOST}/minio/health/live"; do
  echo "MinIO not ready, waiting..."
  sleep 2
done

echo "MinIO is ready. Configuring mc alias..."
mc alias set local "http://${MINIO_HOST}" "${MINIO_ACCESS_KEY}" "${MINIO_SECRET_KEY}"

echo "Creating buckets..."
mc mb --ignore-existing local/mimir
mc mb --ignore-existing local/loki
mc mb --ignore-existing local/tempo
mc mb --ignore-existing local/pyroscope

echo "Buckets created successfully:"
mc ls local/

echo "Done!"
