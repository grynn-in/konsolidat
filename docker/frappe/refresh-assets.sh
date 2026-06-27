#!/bin/bash
# Restore the image-baked asset manifest into the persisted sites/ volume and
# evict the cached copy from Redis. Idempotent and fully non-fatal — safe to run
# on every container start.
#
# Why this is needed: the hashed JS/CSS bundles live in the image layer and are
# always correct in a fresh image, but the manifest mapping logical names ->
# hashes (sites/assets/assets.json) lives in the persistent `frappe_sites`
# volume, which Docker never overwrites. After an image rebuild the stale
# manifest points at hashes that no longer exist and every asset 404s (Desk
# loads unstyled). The configurator runs this on deploy; the backend entrypoint
# runs it on every `web` start so a bare `docker compose up` self-heals too.
#
# Never `set -e` here — callers run under `set -e`, and a stale-manifest refresh
# must never abort a container start. Every step is best-effort.
set -u

cd /home/frappe/frappe-bench || exit 0

if [ ! -f /home/frappe/baked-assets/assets.json ]; then
    echo "WARN: /home/frappe/baked-assets not found — rebuild the image so the manifest is baked (Desk CSS/JS may 404)"
    exit 0
fi

echo "Restoring asset manifest from image bake..."
cp -f /home/frappe/baked-assets/assets.json sites/assets/assets.json
cp -f /home/frappe/baked-assets/assets-rtl.json sites/assets/assets-rtl.json 2>/dev/null || true

# clear-cache does not evict the global Redis `assets_json` key; stale hashes
# 404 CSS/JS. redis-cli is not installed in the runtime image — use the bench venv.
./env/bin/python - <<'PY' >/dev/null 2>&1 || true
import os
import redis

host = os.environ.get("REDIS_CACHE_HOST", "redis_cache")
redis.Redis(host=host, port=6379, socket_timeout=2).delete("assets_json")
PY

# Best-effort site cache flush — only when the site already exists (skips the
# very first deploy, where the configurator creates the site and clears caches).
SITE_NAME="${SITE_NAME:-konsolidat.local}"
if [ -d "sites/${SITE_NAME}" ]; then
    bench --site "$SITE_NAME" clear-cache >/dev/null 2>&1 || true
fi

exit 0
