.PHONY: setup up down dbt seed test logs status clean cube-schema check-gold-domains

COMPOSE = docker compose
COMPOSE_INIT = $(COMPOSE) --profile init

# ---------- Setup ----------

setup: ## Copy .env.example → .env (if missing), build images
	@test -f .env || (cp .env.example .env && echo "Created .env from .env.example — edit it with your credentials")
	$(COMPOSE_INIT) build

# ---------- Lifecycle ----------

up: ## Bring up the full stack (dbt init → all services)
	@test -f .env || (echo "ERROR: No .env file. Run 'make setup' first." && exit 1)
	@echo "=== Starting databases ==="
	$(COMPOSE) up -d clickhouse dagster_postgres
	@echo "=== Waiting for databases to be healthy ==="
	@$(COMPOSE) exec clickhouse clickhouse-client --query "SELECT 'ClickHouse ready'" 2>/dev/null \
		|| (echo "Waiting for ClickHouse..." && sleep 5)
	@echo "=== Running dbt init (deps → seed → build) ==="
	$(COMPOSE_INIT) run --rm dbt_init
	@echo "=== Starting remaining services ==="
	$(COMPOSE) up -d
	@echo ""
	@echo "=== Open EPM is starting ==="
	@echo "  ClickHouse:  http://localhost:8123"
	@echo "  Dagster:     http://localhost:3000"
	@echo "  Cube API:    http://localhost:4000"
	@echo "  Cube SQL:    localhost:15432"
	@echo "  FastAPI:     http://localhost:8080"
	@echo "  Streamlit:   http://localhost:8501"

down: ## Stop all services
	$(COMPOSE_INIT) down

# ---------- dbt ----------

dbt: ## Run dbt build inside container
	$(COMPOSE_INIT) run --rm dbt_init

seed: ## Run dbt seed only
	$(COMPOSE_INIT) run --rm dbt_init bash -c "dbt deps --profiles-dir /app && dbt seed --profiles-dir /app"

cube-schema: ## Regenerate Cube YAML schemas from dbt_project.yml vars
	python scripts/generate_cube_schemas.py

check-gold-domains: ## Assert every gold model carries a known Build Governance domain
	python scripts/check_gold_domains.py dbt_project/dbt_project.yml

# ---------- Monitoring ----------

test: ## Run health checks on all services
	@bash scripts/healthcheck.sh

status: ## Show status of all containers
	$(COMPOSE) ps

logs: ## Tail logs from all services
	$(COMPOSE) logs -f --tail=50

# ---------- Cleanup ----------

clean: ## Remove all containers, volumes, and orphans
	$(COMPOSE_INIT) down -v --remove-orphans

# ---------- Help ----------

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'
