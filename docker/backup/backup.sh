#!/bin/bash
# Nightly backup script for Konsolidat
# Backs up: MariaDB, ClickHouse, Frappe files
set -eo pipefail

BACKUP_DIR="${BACKUP_DIR:-/backups}"
DATE=$(date +%Y-%m-%d_%H%M)
BACKUP_PATH="${BACKUP_DIR}/${DATE}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"

mkdir -p "$BACKUP_PATH"

echo "=== Konsolidat Backup — ${DATE} ==="

# Validate required env vars
if [ -z "${DB_ROOT_PASSWORD:-}" ]; then
    echo "ERROR: DB_ROOT_PASSWORD is not set. Cannot backup MariaDB."
    exit 1
fi

# 1. MariaDB dump
echo "[1/3] Backing up MariaDB..."
mariadb-dump \
    -h "${DB_HOST:-mariadb}" \
    -P "${DB_PORT:-3306}" \
    -u root \
    -p"${DB_ROOT_PASSWORD}" \
    --all-databases \
    --single-transaction \
    --quick \
    | gzip > "${BACKUP_PATH}/mariadb.sql.gz"
echo "  MariaDB: $(du -h "${BACKUP_PATH}/mariadb.sql.gz" | cut -f1)"

# 2. ClickHouse backup
echo "[2/3] Backing up ClickHouse..."
CH_HOST="${CLICKHOUSE_HOST:-clickhouse}"
CH_PORT="${CLICKHOUSE_PORT:-8123}"
CH_USER="${CLICKHOUSE_USER:-default}"
CH_PASS="${CLICKHOUSE_PASSWORD:-open_epm_dev}"

for db in epm epm_staging epm_bronze epm_silver epm_gold; do
    # Get list of tables
    tables=$(curl -sf "http://${CH_HOST}:${CH_PORT}/" \
        -u "${CH_USER}:${CH_PASS}" \
        --data-binary "SELECT name FROM system.tables WHERE database='${db}' FORMAT TabSeparated" 2>/dev/null || echo "")

    if [ -n "$tables" ]; then
        mkdir -p "${BACKUP_PATH}/clickhouse"
        for table in $tables; do
            curl -sf "http://${CH_HOST}:${CH_PORT}/" \
                -u "${CH_USER}:${CH_PASS}" \
                --data-binary "SELECT * FROM ${db}.${table} FORMAT Native" \
                | gzip > "${BACKUP_PATH}/clickhouse/${db}__${table}.native.gz" 2>/dev/null || true
        done
    fi
done
echo "  ClickHouse: $(du -sh "${BACKUP_PATH}/clickhouse/" 2>/dev/null | cut -f1 || echo '0')"

# 3. Frappe site files
echo "[3/3] Backing up Frappe files..."
if [ -d "/home/frappe/frappe-bench/sites" ]; then
    tar czf "${BACKUP_PATH}/frappe_sites.tar.gz" \
        -C /home/frappe/frappe-bench sites/ 2>/dev/null || true
    echo "  Frappe files: $(du -h "${BACKUP_PATH}/frappe_sites.tar.gz" | cut -f1)"
fi

# 4. Upload to S3 if configured
if [ -n "${BACKUP_S3_BUCKET}" ]; then
    echo "[S3] Uploading to ${BACKUP_S3_BUCKET}..."
    if command -v aws >/dev/null 2>&1; then
        aws s3 sync "${BACKUP_PATH}/" "s3://${BACKUP_S3_BUCKET}/${DATE}/" --quiet
        echo "  S3 upload complete."
    else
        echo "  WARNING: aws CLI not found. Skipping S3 upload."
    fi
fi

# 5. Cleanup old backups
echo "Cleaning up backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_DIR}" -maxdepth 1 -type d -mtime "+${RETENTION_DAYS}" -exec rm -rf {} \; 2>/dev/null || true

TOTAL_SIZE=$(du -sh "${BACKUP_PATH}" | cut -f1)
echo ""
echo "=== Backup Complete ==="
echo "Location: ${BACKUP_PATH}"
echo "Total size: ${TOTAL_SIZE}"
echo "Retention: ${RETENTION_DAYS} days"
