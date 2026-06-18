#!/usr/bin/env bash
# =============================================================================
# setup-airbyte.sh — Install Airbyte as a second stack on the same server
# =============================================================================
# Prerequisites:
#   1. Open EPM stack running  (docker compose up -d)
#   2. curl installed
#
# Usage:
#   bash scripts/setup-airbyte.sh
# =============================================================================
set -euo pipefail

# --- Preflight: Open EPM network must exist -----------------------------------
if ! docker network inspect open_epm >/dev/null 2>&1; then
  echo "Error: 'open_epm' network not found."
  echo "Start the Open EPM stack first:  docker compose up -d"
  exit 1
fi

# --- Install abctl if missing ------------------------------------------------
if ! command -v abctl &>/dev/null; then
  echo "Installing Airbyte CLI (abctl)..."
  curl -LsfS https://get.airbyte.com | bash
  echo ""
fi

# --- Install Airbyte on the shared network ------------------------------------
echo "Installing Airbyte (this takes a few minutes on first run)..."
abctl local install --network open_epm

# --- Print connection info ----------------------------------------------------
echo ""
echo "========================================"
echo "  Airbyte is running"
echo "========================================"
echo ""
echo "  UI:  http://localhost:8000"
echo ""
echo "  Default credentials (first login):"
echo "    Username: airbyte"
echo "    Password: password"
echo ""
echo "========================================"
echo "  ClickHouse Destination Settings"
echo "========================================"
echo ""
echo "  Host:      konsolidat_clickhouse"
echo "  HTTP Port: 8123"
echo "  Database:  epm_raw"
echo "  User:      ${CLICKHOUSE_USER:-default}"
echo "  Password:  (from your .env CLICKHOUSE_PASSWORD)"
echo ""
echo "The custom D365 connector is in source-d365-fno/."
echo "Load it via Airbyte's Connector Builder (Settings → Custom Connectors)."
