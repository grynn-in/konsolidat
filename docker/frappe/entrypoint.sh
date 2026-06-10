#!/bin/bash
set -e

cd /home/frappe/frappe-bench

# Configure Redis from environment
bench set-config -g redis_cache "redis://${REDIS_CACHE_HOST:-redis_cache}:6379"
bench set-config -g redis_queue "redis://${REDIS_QUEUE_HOST:-redis_queue}:6379"
bench set-config -g redis_socketio "redis://${REDIS_CACHE_HOST:-redis_cache}:6379"

MODE="${1:-web}"

case "$MODE" in
  web)
    echo "Starting Frappe web server on port 8069..."
    # Use application_with_statics to serve /assets/ via SharedDataMiddleware
    # (no separate nginx needed)
    /home/frappe/frappe-bench/env/bin/gunicorn \
      --bind 0.0.0.0:8069 \
      --workers ${GUNICORN_WORKERS:-4} \
      --timeout 120 \
      --graceful-timeout 30 \
      --chdir /home/frappe/frappe-bench/sites \
      'frappe.app:application_with_statics()'
    ;;
  worker)
    echo "Starting Frappe background worker..."
    bench worker --queue default,short,long
    ;;
  scheduler)
    echo "Starting Frappe scheduler..."
    bench schedule
    ;;
  *)
    echo "Unknown mode: $MODE"
    echo "Usage: entrypoint.sh {web|worker|scheduler}"
    exit 1
    ;;
esac
