#!/usr/bin/env bash
# =============================================================================
# setup-airbyte.sh — Install Airbyte as a second stack on the same server
# =============================================================================
# Airbyte is installed by abctl into its own local Kubernetes (kind) cluster.
# That cluster runs in a separate Docker network from the Open EPM stack, so we
# bridge them by attaching the kind node container to the 'open_epm' network
# after install. Airbyte sync pods then reach ClickHouse over that network.
#
# Prerequisites:
#   1. Open EPM stack running  (docker compose up -d) — creates the 'open_epm' network
#   2. curl + docker installed
#
# Usage:
#   bash scripts/setup-airbyte.sh
# =============================================================================
set -euo pipefail

# ClickHouse's pinned address on the 'open_epm' network (see docker-compose.yml).
# Airbyte pods resolve via CoreDNS (not Docker DNS), so they cannot look up the
# container name — they must use this stable IP.
CH_IP="172.30.0.10"
# Airbyte reaches ClickHouse's INTERNAL container port over the open_epm network,
# which is always 8123 — independent of CLICKHOUSE_HTTP_PORT (that only remaps the
# host-published port and is irrelevant for container-to-container traffic).
CH_HTTP_PORT="8123"

# kind node container that abctl creates for the local Airbyte cluster.
ABCTL_NODE="airbyte-abctl-control-plane"

# --- Preflight: Open EPM network + ClickHouse must be up ----------------------
if ! docker network inspect open_epm >/dev/null 2>&1; then
  echo "Error: 'open_epm' network not found."
  echo "Start the Open EPM stack first:  docker compose up -d"
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qx konsolidat_clickhouse; then
  echo "Error: 'konsolidat_clickhouse' container is not running."
  echo "Start the Open EPM stack first:  docker compose up -d"
  exit 1
fi

# --- Install abctl if missing ------------------------------------------------
if ! command -v abctl &>/dev/null; then
  echo "Installing Airbyte CLI (abctl)..."
  curl -LsfS https://get.airbyte.com | bash
  echo ""
fi

# --- Install Airbyte ----------------------------------------------------------
# NOTE: abctl has no host-networking flag; it always provisions its own kind
# cluster. We bridge to ClickHouse in the next step.
echo "Installing Airbyte (this takes a few minutes on first run)..."
abctl local install

# --- Bridge the Airbyte kind cluster to the open_epm network ------------------
NODE="$(docker ps --filter "name=${ABCTL_NODE}" --format '{{.Names}}' | head -1)"
NODE="${NODE:-$ABCTL_NODE}"

if docker network inspect open_epm --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' 2>/dev/null | grep -qx "$NODE"; then
  echo "Airbyte node '$NODE' already attached to 'open_epm'."
else
  echo "Attaching Airbyte node '$NODE' to the 'open_epm' network..."
  docker network connect open_epm "$NODE"
fi

# --- Load CLICKHOUSE_USER from .env for accurate output -----------------------
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

# --- Print connection info ----------------------------------------------------
echo ""
echo "========================================"
echo "  Airbyte is running"
echo "========================================"
echo ""
echo "  UI:  http://localhost:8000"
echo ""
echo "  Login credentials:"
abctl local credentials || echo "    (run 'abctl local credentials' to retrieve them)"
echo ""
echo "========================================"
echo "  ClickHouse Destination Settings"
echo "========================================"
echo ""
echo "  Host:      ${CH_IP}    # pinned IP on the open_epm network — NOT a hostname"
echo "  HTTP Port: ${CH_HTTP_PORT}"
echo "  Database:  epm_raw"
echo "  User:      ${CLICKHOUSE_USER:-default}"
echo "  Password:  (from your .env CLICKHOUSE_PASSWORD)"
echo ""
echo "The custom D365 connector is in source-d365-fno/."
echo "Load it via Airbyte's Connector Builder (Settings → Custom Connectors)."
