# Konsolidat

Open-source Corporate Performance Management (CPM) for Dynamics 365 Finance & Operations. Multi-entity consolidation, Excel-native budgeting, driver-based allocations, and scenario modeling — at 3% of the cost of Tagetik or OneStream.

## Architecture

```
D365 F&O (OData)
    |
    v
Airbyte (ELT) ──> ClickHouse (Analytical DW)
                        |
                   dbt Core (Transform)
                   Bronze → Silver → Gold
                        |
              ┌─────────┼──────────┐
              v                    v
           Excel               Frappe (Konsol)
      (ODBC → ClickHouse)     Pipeline Control + UI
```

### Data Flow (Medallion Architecture)

| Layer | Schema | Purpose | Materialization |
|-------|--------|---------|-----------------|
| **Raw** | `epm_bronze` (Airbyte) | OData entities as-is from D365 | Airbyte-managed |
| **Staging** | `staging` | Field renames, joins, JSON parsing, rate scaling | Views |
| **Bronze** | `bronze` | Type-cast, snake_case, dimension mapping | Tables |
| **Silver** | `silver` | Deduplicated, standardized trial balance | Tables |
| **Gold** | `gold` | Business logic: consolidation, allocations, variance | Tables |

### Components

| Component | Purpose | Port | Technology |
|-----------|---------|------|------------|
| **ClickHouse** | Columnar analytical warehouse | 8123 (HTTP), 9000 (native) | ClickHouse 24.8 |
| **Airbyte** | D365 OData extraction (via abctl) | 8000 | Airbyte OSS |
| **dbt Core** | SQL transformations (bronze→gold) | CLI | dbt-clickhouse |
| **Frappe (Konsol)** | Pipeline control, settings, UI | 8069 | Frappe Framework |
| **Excel** | Reporting via ODBC direct to ClickHouse | — | ClickHouse ODBC |

---

## Features

### Multi-Entity Consolidation

Full IFRS/GAAP consolidation pipeline:

- **Currency translation** — Balance sheet at closing rate, P&L at average rate
- **CTA calculation** — Automatic Currency Translation Adjustment as a balancing plug
- **Minority interest (NCI)** — Group vs non-controlling interest split based on ownership %
- **Intercompany elimination** — Rule-based IC receivable/payable and revenue/COGS netting
- **Top-side adjustments** — Manual consolidation journal entries (goodwill, fair value, reclassifications)
- **Fully consolidated TB** — Unions entity balances + IC eliminations + CTA + top-side into one view

#### Consolidation Group Setup

Edit `dbt_project/seeds/consolidation_groups.csv`:

```csv
consolidation_group,data_area_id,entity_name,ownership_pct,reporting_currency,consolidation_method
GROUP_CORP,USMF,Contoso US,100.00,USD,full
GROUP_CORP,DEMF,Contoso DE,100.00,USD,full
GROUP_CORP,GBMF,Contoso UK,80.00,USD,full
GROUP_CORP,JPMF,Contoso JP,51.00,USD,full
```

### Driver-Based Cost Allocations

Multi-step cascading allocation engine:

1. **Step 1**: IT costs allocated by headcount
2. **Step 2**: Facility costs allocated by sqm
3. **Step 3**: Management fee allocated by revenue

Each step's pool includes amounts allocated from all prior steps (cascading).

### Budgeting & Scenarios

- Annual budgets spread to 12 periods using configurable profiles
- Actual vs budget variance analysis with favorable/unfavorable indicators
- Revenue: favorable when actual > budget; Expense: favorable when actual < budget

### Excel Integration

Excel connects directly to ClickHouse via ODBC driver (port 8123):

1. Install ClickHouse ODBC driver (64-bit)
2. DSN: `Host=localhost; Port=8123; Database=epm_gold; User=default; Password=<password>`
3. Excel → Data → Get Data → From ODBC → Load tables → PivotTable

**Available gold tables**: `gold_trial_balance`, `gold_pnl_by_period`, `gold_consolidated_tb`, `gold_allocation_results`, `gold_variance_analysis`

---

## Setup Guide

### Prerequisites

- Docker & Docker Compose
- Python 3.10+
- Frappe bench (v15+)
- Git

### 1. Clone and Configure

```bash
git clone https://github.com/grynn-in/konsolidat.git
cd konsolidat
cp .env.example .env
# Edit .env with your D365 credentials and ClickHouse password
```

### 2. Start ClickHouse

```bash
docker compose up -d
```

### 3. Install Airbyte

```bash
curl -LsfS https://get.airbyte.com | bash -
abctl local install
abctl local credentials
```

Open http://localhost:8000, configure the D365 source, set ClickHouse as destination.

### 4. Run dbt

```bash
cd dbt_project
pip install dbt-clickhouse
dbt deps
dbt seed    # Load allocation rules, consolidation groups, spread profiles
dbt build   # Build all models + run tests
```

### 5. Install Konsol (Frappe App)

```bash
cd /home/pd/frappe-bench
bench --site epm.local install-app konsol
bench migrate
```

Navigate to `http://localhost:8069/app/pipeline-run` to trigger extract + transform.

### 6. Connect Excel

Install ClickHouse ODBC driver, create a DSN pointing to `localhost:8123`, database `epm_gold`. See [Excel User Guide](docs/excel-user-guide.md).

---

## Project Structure

```
konsolidat/
├── dbt_project/
│   ├── models/
│   │   ├── staging/           # D365 transform views (raw → clean)
│   │   ├── bronze/            # Type-cast tables
│   │   ├── silver/            # Standardized trial balance, dimensions
│   │   └── gold/              # Consolidation, allocations, variance, budgets
│   ├── seeds/                 # CSV config: rules, groups, profiles, drivers
│   ├── macros/                # Allocation engine, dimension/measure helpers
│   └── tests/                 # Data quality assertions
├── source-d365-fno/           # Airbyte custom source connector (Python CDK)
├── docker/                    # Dockerfiles
├── scripts/                   # Utility scripts
├── docs/                      # PRDs, guides
├── tests/                     # Integration tests
└── docker-compose.yml         # ClickHouse only
```

Frappe app lives at `/home/pd/frappe-bench/apps/konsol/`.

---

## Roadmap

- **Excel Online Add-in** — Browser-based Excel integration
- **Entra ID SSO** — Azure AD authentication via Frappe Social Login
- **Cash Flow Forecasting** — Direct/indirect method from GL data
- **Intercompany Matching** — Pre-elimination IC balance reconciliation
- **Audit Trail** — Full change tracking on consolidation adjustments

## License

MIT
