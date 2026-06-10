#!/bin/bash
# One-shot configurator: creates Frappe site, installs konsol app, loads demo data
set -e

cd /home/frappe/frappe-bench

SITE_NAME="${SITE_NAME:-konsolidat.local}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin123}"
DB_HOST="${DB_HOST:-mariadb}"
DB_PORT="${DB_PORT:-3306}"
DB_ROOT_PASSWORD="${DB_ROOT_PASSWORD:-rootpassword}"

echo "=== Konsolidat Configurator ==="
echo "Site: ${SITE_NAME}"
echo "DB Host: ${DB_HOST}:${DB_PORT}"

# Wait for MariaDB to be ready
echo "Waiting for MariaDB..."
for i in $(seq 1 60); do
    if mariadb -h "$DB_HOST" -P "$DB_PORT" -u root -p"$DB_ROOT_PASSWORD" -e "SELECT 1" >/dev/null 2>&1; then
        echo "MariaDB is ready."
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo "ERROR: MariaDB not ready after 60 seconds."
        exit 1
    fi
    sleep 1
done

# Wait for Redis (TCP check — redis-cli not installed in image)
echo "Waiting for Redis..."
REDIS_HOST="${REDIS_CACHE_HOST:-redis_cache}"
for i in $(seq 1 30); do
    if bash -c "exec 3<>/dev/tcp/${REDIS_HOST}/6379" 2>/dev/null; then
        echo "Redis is ready."
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "ERROR: Redis not ready after 30 seconds."
        exit 1
    fi
    sleep 1
done

# Wait for ClickHouse
echo "Waiting for ClickHouse..."
CH_HOST="${CLICKHOUSE_HOST:-clickhouse}"
CH_PORT="${CLICKHOUSE_PORT:-8123}"
for i in $(seq 1 60); do
    if curl -sf "http://${CH_HOST}:${CH_PORT}/ping" >/dev/null 2>&1; then
        echo "ClickHouse is ready."
        break
    fi
    if [ "$i" -eq 60 ]; then
        echo "WARNING: ClickHouse not ready. Continuing anyway (sync will retry)."
        break
    fi
    sleep 1
done

# Configure Redis connections
bench set-config -g redis_cache "redis://${REDIS_CACHE_HOST:-redis_cache}:6379"
bench set-config -g redis_queue "redis://${REDIS_QUEUE_HOST:-redis_queue}:6379"
bench set-config -g redis_socketio "redis://${REDIS_CACHE_HOST:-redis_cache}:6379"

# Check if site already exists
if [ -d "sites/${SITE_NAME}" ]; then
    echo "Site ${SITE_NAME} already exists. Running migrations..."
    bench --site "$SITE_NAME" migrate
else
    echo "Creating new site: ${SITE_NAME}..."
    bench new-site "$SITE_NAME" \
        --db-host "$DB_HOST" \
        --db-port "$DB_PORT" \
        --db-root-password "$DB_ROOT_PASSWORD" \
        --admin-password "$ADMIN_PASSWORD" \
        --no-mariadb-socket

    echo "Installing konsol app..."
    bench --site "$SITE_NAME" install-app konsol

    echo "Setting site as default..."
    bench use "$SITE_NAME"
fi

# Configure EPM Settings with ClickHouse connection
echo "Configuring ClickHouse connection in EPM Settings..."
bench --site "$SITE_NAME" execute konsol.install.setup_epm_settings \
    --kwargs "{\"ch_host\": \"${CH_HOST}\", \"ch_port\": ${CH_PORT}, \"ch_user\": \"${CLICKHOUSE_USER:-default}\", \"ch_password\": \"${CLICKHOUSE_PASSWORD:-open_epm_dev}\"}" \
    2>/dev/null || echo "EPM Settings setup skipped (install.py may not exist yet)"

echo ""
echo "=== Configurator Complete ==="
echo "Site: ${SITE_NAME}"
echo "Admin: Administrator / ${ADMIN_PASSWORD}"
