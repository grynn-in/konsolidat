#!/bin/bash
# =============================================================================
# Konsolidat — One-Click Deployment
# =============================================================================
# Usage:
#   ./deploy.sh                          First-time setup (everything)
#   ./deploy.sh --domain epm.company.com Setup with custom domain + auto-SSL
#   ./deploy.sh backup                   Run backup now
#   ./deploy.sh restore --from <path>    Restore from backup
#   ./deploy.sh status                   Show service status
#   ./deploy.sh logs                     Tail all logs
#   ./deploy.sh down                     Stop everything
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ---------------------------------------------------------------------------
# Sub-commands
# ---------------------------------------------------------------------------
case "${1:-}" in
  backup)
    info "Running backup..."
    docker compose --profile backup run --rm backup
    exit 0
    ;;
  restore)
    if [ -z "${3:-}" ] || [ "$2" != "--from" ]; then
      err "Usage: ./deploy.sh restore --from /path/to/backup"
      exit 1
    fi
    RESTORE_PATH="$3"
    info "Restoring from ${RESTORE_PATH}..."

    # Restore MariaDB
    if [ -f "${RESTORE_PATH}/mariadb.sql.gz" ]; then
      info "Restoring MariaDB..."
      gunzip -c "${RESTORE_PATH}/mariadb.sql.gz" | \
        docker compose exec -T mariadb mariadb -u root -p"${DB_ROOT_PASSWORD:-rootpassword}"
      ok "MariaDB restored."
    fi

    # Restore Frappe files
    if [ -f "${RESTORE_PATH}/frappe_sites.tar.gz" ]; then
      info "Restoring Frappe files..."
      docker compose cp "${RESTORE_PATH}/frappe_sites.tar.gz" frappe_backend:/tmp/
      docker compose exec frappe_backend bash -c "cd /home/frappe/frappe-bench && tar xzf /tmp/frappe_sites.tar.gz"
      ok "Frappe files restored."
    fi

    # Restore ClickHouse
    if [ -d "${RESTORE_PATH}/clickhouse" ]; then
      info "Restoring ClickHouse tables..."
      for file in "${RESTORE_PATH}/clickhouse/"*.native.gz; do
        basename_noext=$(basename "$file" .native.gz)
        db=$(echo "$basename_noext" | cut -d'_' -f1-2)
        table=$(echo "$basename_noext" | cut -d'_' -f3-)
        info "  Restoring ${db}.${table}..."
        gunzip -c "$file" | curl -sf "http://localhost:${CLICKHOUSE_HTTP_PORT:-8123}/?user=${CLICKHOUSE_USER:-default}&password=${CLICKHOUSE_PASSWORD:-open_epm_dev}" \
          --data-binary @- -H "X-ClickHouse-Query: INSERT INTO ${db}.${table} FORMAT Native" || true
      done
      ok "ClickHouse restored."
    fi

    ok "Restore complete. Restart services: docker compose restart"
    exit 0
    ;;
  status)
    docker compose ps
    exit 0
    ;;
  logs)
    docker compose logs -f --tail=50
    exit 0
    ;;
  down)
    docker compose down
    exit 0
    ;;
esac

# ---------------------------------------------------------------------------
# Parse flags
# ---------------------------------------------------------------------------
DOMAIN=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --domain)
      DOMAIN="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║         Konsolidat — One-Click Deploy           ║${NC}"
echo -e "${CYAN}║     Excellent analysis thrives on Excel          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
echo ""

# Check Docker
if ! command -v docker &>/dev/null; then
  err "Docker not found. Install it first:"
  echo "  curl -fsSL https://get.docker.com | sh"
  exit 1
fi

# Check Docker Compose
if ! docker compose version &>/dev/null; then
  err "Docker Compose not found. It should come with Docker."
  exit 1
fi

ok "Docker $(docker --version | grep -oP '\d+\.\d+\.\d+')"
ok "Docker Compose $(docker compose version --short)"

# ---------------------------------------------------------------------------
# Generate .env if needed
# ---------------------------------------------------------------------------
if [ ! -f .env ]; then
  info "Generating .env with random passwords..."
  cp .env.example .env

  # Generate random passwords
  GENERATED_ADMIN_PW=$(openssl rand -base64 12 | tr -d '/+=' | head -c 16)
  GENERATED_DB_PW=$(openssl rand -base64 12 | tr -d '/+=' | head -c 16)
  GENERATED_CH_PW=$(openssl rand -base64 12 | tr -d '/+=' | head -c 16)
  GENERATED_CUBEJS_SECRET=$(openssl rand -hex 16)

  sed -i "s|ADMIN_PASSWORD=.*|ADMIN_PASSWORD=${GENERATED_ADMIN_PW}|" .env
  sed -i "s|DB_ROOT_PASSWORD=.*|DB_ROOT_PASSWORD=${GENERATED_DB_PW}|" .env
  sed -i "s|CLICKHOUSE_PASSWORD=.*|CLICKHOUSE_PASSWORD=${GENERATED_CH_PW}|" .env
  sed -i "s|CUBEJS_API_SECRET=.*|CUBEJS_API_SECRET=${GENERATED_CUBEJS_SECRET}|" .env

  if [ -n "$DOMAIN" ]; then
    sed -i "s|SITE_DOMAIN=.*|SITE_DOMAIN=${DOMAIN}|" .env
  fi

  ok "Generated .env with secure passwords"
else
  ok "Using existing .env"
  if [ -n "$DOMAIN" ]; then
    sed -i "s|SITE_DOMAIN=.*|SITE_DOMAIN=${DOMAIN}|" .env
  fi
fi

# Source env for printing later
set -a
source .env
set +a

# ---------------------------------------------------------------------------
# Step 1: Start infrastructure
# ---------------------------------------------------------------------------
echo ""
info "Step 1/5: Starting infrastructure (MariaDB, Redis, ClickHouse)..."
docker compose up -d mariadb redis_cache redis_queue clickhouse

# Wait for all healthchecks
info "Waiting for services to be healthy..."
for svc in mariadb redis_cache redis_queue clickhouse; do
  for i in $(seq 1 120); do
    status=$(docker inspect --format='{{.State.Health.Status}}' "konsolidat_${svc}" 2>/dev/null || echo "starting")
    if [ "$status" = "healthy" ]; then
      ok "${svc} is healthy"
      break
    fi
    if [ "$i" -eq 120 ]; then
      err "${svc} failed to become healthy after 120s"
      docker compose logs "$svc" --tail=20
      exit 1
    fi
    sleep 1
  done
done

# ---------------------------------------------------------------------------
# Step 2: Build Frappe image
# ---------------------------------------------------------------------------
echo ""
info "Step 2/5: Building Frappe + Konsol image (this takes a few minutes on first run)..."
docker compose build frappe_backend

# ---------------------------------------------------------------------------
# Step 3: Run configurator (create site, install app)
# ---------------------------------------------------------------------------
echo ""
info "Step 3/5: Setting up Frappe site and installing Konsol app..."
docker compose --profile setup run --rm configurator

# ---------------------------------------------------------------------------
# Step 4: Start application services
# ---------------------------------------------------------------------------
echo ""
info "Step 4/5: Starting application services..."
docker compose up -d frappe_backend frappe_worker frappe_scheduler cubejs caddy

# Wait for Frappe to respond
info "Waiting for Frappe to start..."
for i in $(seq 1 60); do
  if curl -sf "http://localhost:${FRAPPE_PORT:-8069}/api/method/ping" >/dev/null 2>&1; then
    ok "Frappe is responding"
    break
  fi
  if [ "$i" -eq 60 ]; then
    warn "Frappe not responding yet (may still be starting). Check: docker compose logs frappe_backend"
  fi
  sleep 2
done

# ---------------------------------------------------------------------------
# Step 5: Run dbt seed + build
# ---------------------------------------------------------------------------
echo ""
info "Step 5/5: Running dbt build (seeding demo data + building gold models)..."
docker compose --profile setup run --rm dbt_init || warn "dbt build had warnings (this is normal for demo data)"

# ---------------------------------------------------------------------------
# Done!
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Konsolidat is ready!                     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""

if [ -n "$DOMAIN" ]; then
  echo -e "  ${CYAN}Frappe:${NC}     https://${DOMAIN}"
  echo -e "  ${CYAN}Cube.js:${NC}    https://${DOMAIN}:4443"
else
  echo -e "  ${CYAN}Frappe:${NC}     http://localhost:${FRAPPE_PORT:-8069}"
  echo -e "  ${CYAN}Cube.js:${NC}    http://localhost:${CUBEJS_PORT:-4000}"
fi
echo -e "  ${CYAN}Excel ODBC:${NC} localhost:${EXCEL_ODBC_PORT:-15432}"
echo ""
echo -e "  ${CYAN}Admin login:${NC} Administrator / ${ADMIN_PASSWORD:-admin123}"
echo ""
echo -e "  ${YELLOW}Commands:${NC}"
echo -e "    ./deploy.sh status     Show service status"
echo -e "    ./deploy.sh backup     Run backup now"
echo -e "    ./deploy.sh logs       Tail logs"
echo -e "    ./deploy.sh down       Stop everything"
echo ""

# Save credentials to a file for reference
cat > .credentials <<EOF
# Konsolidat Credentials (generated by deploy.sh)
# Keep this file secure!

Frappe Admin:     Administrator / ${ADMIN_PASSWORD:-admin123}
MariaDB Root:     root / ${DB_ROOT_PASSWORD:-rootpassword}
ClickHouse:       ${CLICKHOUSE_USER:-default} / ${CLICKHOUSE_PASSWORD:-open_epm_dev}
Cube.js Secret:   ${CUBEJS_API_SECRET:-konsolidat-dev-secret}

URLs:
  Frappe:     http://localhost:${FRAPPE_PORT:-8069}
  Cube.js:    http://localhost:${CUBEJS_PORT:-4000}
  Excel ODBC: localhost:${EXCEL_ODBC_PORT:-15432}
EOF
chmod 600 .credentials
info "Credentials saved to .credentials (chmod 600)"
