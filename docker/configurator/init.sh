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
    if bash -c "exec 3<>/dev/tcp/${REDIS_HOST}/6379; printf 'PING\r\n' >&3; read -t 2 reply <&3; [[ \$reply == *PONG* ]]" 2>/dev/null; then
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

# Alias `localhost` to this site so the Excel Office.js add-in works out of the
# box. The add-in manifest targets http://localhost:8069 (Office.js only allows
# plain HTTP for the literal host `localhost`), but Frappe routes by Host header
# and does not serve the default site for a bare `Host: localhost` on the
# gunicorn port — so those URLs 404 on a fresh deploy. A sites/localhost symlink
# to the real site directory makes Frappe resolve `localhost` to this site.
# Idempotent; skipped when the site already is `localhost`. Only (re)point when
# sites/localhost is absent or already a symlink — never clobber a real site
# directory named `localhost`, and (under `set -e`) never let `ln` abort the deploy.
if [ "$SITE_NAME" != "localhost" ]; then
    if [ -L sites/localhost ] || [ ! -e sites/localhost ]; then
        echo "Aliasing host 'localhost' -> ${SITE_NAME} (Excel add-in / local access)..."
        ln -sfn "$SITE_NAME" sites/localhost
    else
        echo "WARN: sites/localhost exists as a real path; skipping localhost alias."
    fi
fi

# Configure EPM Settings with ClickHouse connection
echo "Configuring ClickHouse connection in EPM Settings..."
bench --site "$SITE_NAME" execute konsol.install.setup_epm_settings \
    --kwargs "{\"ch_host\": \"${CH_HOST}\", \"ch_port\": ${CH_PORT}, \"ch_user\": \"${CLICKHOUSE_USER:-default}\", \"ch_password\": \"${CLICKHOUSE_PASSWORD:-open_epm_dev}\"}" \
    2>/dev/null || echo "EPM Settings setup skipped (install.py may not exist yet)"

# Sync scheduled jobs from app hooks.
# `bench migrate` does not reliably create the Scheduled Job Type rows for an
# app's scheduler_events crons on an existing site, so konsol's cron jobs
# (e.g. close_run reaper, connector-health refresh) silently never register.
# Run sync_jobs explicitly so every deploy reconciles the cron registry.
echo "Syncing scheduled jobs from hooks..."
bench --site "$SITE_NAME" execute \
    frappe.core.doctype.scheduled_job_type.scheduled_job_type.sync_jobs \
    2>/dev/null || echo "WARN: scheduled job sync failed"

# Restore the image-baked asset manifest into the persisted sites/ volume.
#
# Why this, not `bench build`: the hashed JS/CSS bundles live in the image
# layer (sites/assets/frappe -> apps/frappe/.../public/dist) and are always
# correct in a fresh image. But the manifest that maps logical names to those
# hashes (sites/assets/assets.json) lives in the persistent `frappe_sites`
# volume, which Docker never overwrites — so after an image rebuild the stale
# manifest points at hashes that no longer exist and every asset 404s (Desk
# loads with no CSS/JS).
#
# `bench build` cannot fix this here: esbuild does NOT run in the runtime image
# (no dev toolchain), so `bench build` only compiles translations and *cleans*
# dist/css without emitting replacements — making CSS worse, not better. The
# real fix is to copy the manifest baked into the image at build time (see
# docker/frappe/Dockerfile -> /home/frappe/baked-assets) over the stale volume
# copy. Non-fatal so a missing bake never halts the deploy.
echo "Restoring asset manifest from image bake..."
if [ -f /home/frappe/baked-assets/assets.json ]; then
    cp -f /home/frappe/baked-assets/assets.json sites/assets/assets.json
    cp -f /home/frappe/baked-assets/assets-rtl.json sites/assets/assets-rtl.json 2>/dev/null || true
    bench --site "$SITE_NAME" clear-cache >/dev/null 2>&1 || true
    # clear-cache does not evict the global Redis assets_json key; stale hashes 404 CSS/JS.
    # redis-cli is not installed in the runtime image — use the bench venv instead.
    ./env/bin/python - <<'PY' >/dev/null 2>&1 || true
import os
import redis

host = os.environ.get("REDIS_CACHE_HOST", "redis_cache")
redis.Redis(host=host, port=6379, socket_timeout=2).delete("assets_json")
PY
else
    echo "WARN: /home/frappe/baked-assets not found — rebuild the image so the manifest is baked (Desk CSS/JS may 404)"
fi

echo ""
echo "=== Configurator Complete ==="
echo "Site: ${SITE_NAME}"
echo "Admin: Administrator / ${ADMIN_PASSWORD}"
