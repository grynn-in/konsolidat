#!/usr/bin/env bash
# Print the URL deploy.sh uses to reach Frappe from the host. FRAPPE_PORT is
# either a bare port (8069) or host:port (127.0.0.1:8069, which keeps Frappe
# off the public interface on a server; Deepak Pai, 8 Nov 2026).
set -euo pipefail
port="${FRAPPE_PORT:-8069}"
case "$port" in
  *:*) printf 'http://%s' "$port" ;;
  *)   printf 'http://localhost:%s' "$port" ;;
esac
