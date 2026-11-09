#!/usr/bin/env bash
# Refuse to create a site whose Administrator password is known (Deepak Pai,
# 8 Nov 2026). Run by init.sh before `bench new-site`, and only then: a migrate
# of an existing site does not read ADMIN_PASSWORD.
# Refused: unset or blank; `admin123` (the old default, public in this repo);
# any `not-stored-here...` placeholder (a .env convention for stacks whose site
# already exists, also public). Exit 0 when the value is usable, 1 otherwise.
# The refused value is never printed.
set -euo pipefail
value="${ADMIN_PASSWORD:-}"
trimmed="$(printf '%s' "$value" | tr -d '[:space:]')"
reason=""
if [ -z "$trimmed" ]; then
  reason="ADMIN_PASSWORD is not set"
elif [ "$value" = "admin123" ]; then
  reason="ADMIN_PASSWORD is the old public default"
elif [[ "$value" == not-stored-here* ]]; then
  reason="ADMIN_PASSWORD is a placeholder for a site that already exists, and it is public"
fi
if [ -n "$reason" ]; then
  echo "[ERROR] Refusing to create a new site: $reason." >&2
  echo "        Set ADMIN_PASSWORD in .env to a password of your own for this one run," >&2
  echo "        then remove it again once the site exists (a migrate does not need it)." >&2
  exit 1
fi
