#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

PASS=0
FAIL=0

check_service() {
  local name="$1"
  local cmd="$2"

  if eval "$cmd" > /dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} ${name}"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}✗${NC} ${name}"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Open EPM Health Check ==="
echo ""

check_service "ClickHouse (HTTP :8123)" \
  "curl -sf http://localhost:8123/ping"

check_service "ClickHouse (databases)" \
  "curl -sf 'http://localhost:8123/?query=SELECT+count()+FROM+system.databases'"

check_service "Frappe (Web :8069)" \
  "curl -sf http://localhost:8069/api/method/ping"

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
