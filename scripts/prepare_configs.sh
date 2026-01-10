#!/bin/bash
# scripts/prepare_configs.sh
# Purpose: Substitute environment variables in config files before Docker Compose startup.
# This ensures that credentials from .env are correctly propagated to the backend service configurations.

set -e

# Path to .env file (assume script runs from project root)
ENV_FILE=./.env

if [ -f "$ENV_FILE" ]; then
  echo "Loading environment variables from $ENV_FILE..."
  # Export variables from .env if not already set
  # Using safe export avoiding comments
  # Export variables from .env manually to avoid shell interpolation of symbols like $
  # We use grep and cut to get the raw values
  export MINIO_ROOT_USER=$(grep '^MINIO_ROOT_USER=' "$ENV_FILE" | cut -d'=' -f2-)
  export MINIO_ROOT_PASSWORD=$(grep '^MINIO_ROOT_PASSWORD=' "$ENV_FILE" | cut -d'=' -f2-)
else
  echo "Warning: .env file not found. Relying on existing environment variables."
fi

# Validate Required variables
if [ -z "$MINIO_ROOT_USER" ] || [ -z "$MINIO_ROOT_PASSWORD" ]; then
    echo "Error: MINIO_ROOT_USER or MINIO_ROOT_PASSWORD are missing!"
    exit 1
fi

echo "Substituting variables in configuration files..."

# List of files to process
FILES="configs/loki.yaml configs/mimir.yaml configs/tempo.yaml configs/pyroscope.yaml configs/nginx/nginx.conf"
# Variables to substitution (space separated list of $VAR)
VARS='$MINIO_ROOT_USER $MINIO_ROOT_PASSWORD $DOMAIN'

for file in $FILES; do
  if [ -f "$file" ]; then
    echo "Processing $file..."
    # Use envsubst to replace only specific variables
    # We write to a tmp file then move, to support re-running safely (provided source is template-like)
    # WARNING: Since we overwrite the file, subsequent runs will have VALUES not KEYS.
    # This is fine for deployment. If we redeploy, 'git reset --hard' (added to manifest) restores the keys.
    envsubst "$VARS" < "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  else
    echo "Warning: Config file $file not found!"
  fi
done

echo "Configuration preparation complete."
