#!/usr/bin/env bash
set -euo pipefail

CLICKHOUSE_HOST="${CLICKHOUSE_HOST:-clickhouse}"
CLICKHOUSE_PORT="${CLICKHOUSE_PORT:-8123}"
MAX_RETRIES=30
RETRY_INTERVAL=2

echo "=== dbt-init: waiting for ClickHouse at ${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT} ==="

retries=0
until curl -sf "http://${CLICKHOUSE_HOST}:${CLICKHOUSE_PORT}/ping" > /dev/null 2>&1; do
  retries=$((retries + 1))
  if [ "$retries" -ge "$MAX_RETRIES" ]; then
    echo "ERROR: ClickHouse not ready after ${MAX_RETRIES} attempts. Exiting."
    exit 1
  fi
  echo "  Attempt ${retries}/${MAX_RETRIES} - ClickHouse not ready, retrying in ${RETRY_INTERVAL}s..."
  sleep "$RETRY_INTERVAL"
done

echo "=== ClickHouse is ready ==="

cd /app

echo "=== Running dbt deps ==="
dbt deps --profiles-dir /app

echo "=== Running dbt seed ==="
dbt seed --profiles-dir /app

echo "=== Running dbt build ==="
dbt build --profiles-dir /app

echo "=== dbt-init complete ==="
