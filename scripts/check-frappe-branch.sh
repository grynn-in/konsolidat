#!/usr/bin/env bash
# Refuse a .env that names a Frappe branch the image was not built for
# (konsol#358). docker/frappe/Dockerfile is tied to Frappe v16: Python 3.14,
# Node 24, version-16. Compose no longer passes FRAPPE_BRANCH, so a stale
# `FRAPPE_BRANCH=version-15` line would otherwise be ignored without a word.
# Usage: check-frappe-branch.sh <env-file>. Exit 0 when the line is absent or
# names the supported branch; exit 1 with instructions otherwise.
set -euo pipefail
SUPPORTED="version-16"
ENV_FILE="${1:?usage: check-frappe-branch.sh <env-file>}"
[ -f "$ENV_FILE" ] || exit 0
value=$(grep -E '^FRAPPE_BRANCH=' "$ENV_FILE" | tail -n 1 | cut -d= -f2- | tr -d '"'"'"' \r' || true)
if [ -n "$value" ] && [ "$value" != "$SUPPORTED" ]; then
  echo "[ERROR] $ENV_FILE sets FRAPPE_BRANCH=$value, but this image builds Frappe $SUPPORTED only." >&2
  echo "        Back up the site first (bench --site <site> backup --with-files): the" >&2
  echo "        $SUPPORTED migrate cannot be undone. Then delete the FRAPPE_BRANCH line" >&2
  echo "        from $ENV_FILE (or set it to $SUPPORTED) and re-run." >&2
  exit 1
fi
