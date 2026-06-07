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
                   Cube.js (Semantic Layer)
                   REST API + SQL Wire Protocol
                        |
              ┌─────────┼──────────┐
              v         v          v
           Excel    Frappe App   Streamlit
         (PivotTables) (planned)  (Admin)
              |
         FastAPI (Write-back: Budget, Scenarios, Adjustments)
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
| **Airbyte** | D365 OData extraction (via abctl) | 8000 | Airbyte OSS 2.1 |
| **dbt Core** | SQL transformations (bronze→gold) | CLI | dbt-clickhouse |
| **Cube** | Semantic layer + SQL API for Excel | 4000 (API), 15432 (SQL) | Cube.js 0.36 |
| **Dagster** | Pipeline orchestration | 3000 | Dagster OSS |
| **FastAPI** | Budget/scenario write-back API | 8080 | Python |
| **Streamlit** | Admin UI (rules, data quality) | 8501 | Python |
| **Frappe** | Application layer (planned) | 8069 | Frappe Framework |

---

## Features

### Multi-Entity Consolidation

Full IFRS/GAAP consolidation pipeline:

- **Currency translation** — Balance sheet at closing rate, P&L at average rate (PRD-1)
- **CTA calculation** — Automatic Currency Translation Adjustment as a balancing plug (PRD-2)
- **Minority interest (NCI)** — Group vs non-controlling interest split based on ownership % (PRD-4)
- **Intercompany elimination** — Rule-based IC receivable/payable and revenue/COGS netting (PRD-3)
- **Top-side adjustments** — Manual consolidation journal entries (goodwill, fair value, reclassifications) (PRD-5)
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

- `ownership_pct < 100` triggers NCI split: `group_amount = translated × ownership%`, `nci_amount = translated × (1 - ownership%)`
- Exchange rates come from D365 via Airbyte (`ExchangeRates` entity)
- Rate selection: BS accounts use closing rate, P&L accounts use average rate

#### Intercompany Elimination Rules

Edit `dbt_project/seeds/ic_elimination_rules.csv`:

```csv
rule_id,rule_name,debit_account,credit_account,debit_entity_pattern,credit_entity_pattern
IC_001,IC Receivable/Payable,1300,2100,*,*
IC_002,IC Revenue/COGS,4000,5000,*,*
```

#### Top-Side Adjustments

Edit `dbt_project/seeds/consolidation_adjustments.csv` or POST via API:

```csv
consolidation_group,adjustment_type,journal_id,data_area_id,fiscal_year,fiscal_period,main_account,debit_amount,credit_amount,description,posted_by
GROUP_CORP,topside,ADJ-001,USMF,2024,12,3100,500000.00,0.00,Goodwill adjustment,controller@co.com
GROUP_CORP,topside,ADJ-001,USMF,2024,12,1800,0.00,500000.00,Goodwill adjustment,controller@co.com
```

### Driver-Based Cost Allocations

Multi-step cascading allocation engine (PRD-3):

1. **Step 1**: IT costs (account 7100, cost center IT) allocated by headcount
2. **Step 2**: Facility costs (account 7200) + IT costs allocated to FACILITY, allocated by sqm
3. **Step 3**: Management fee (account 7300) + costs from steps 1-2, allocated by revenue

Each step's pool includes amounts allocated from all prior steps (cascading).

#### Allocation Rule Setup

Edit `dbt_project/seeds/allocation_rules.csv`:

```csv
allocation_rule_id,rule_name,step_order,source_account,source_cost_center,driver_type,target_account,description
ALLOC_001,IT Cost Allocation,1,7100,IT,headcount,7100,Allocate IT costs by headcount
ALLOC_002,Facility Cost Allocation,2,7200,FACILITY,sqm,7200,Allocate facility costs by sqm
ALLOC_003,Management Fee,3,7300,MGMT,revenue,7300,Allocate mgmt costs by revenue
```

#### Allocation Drivers

Create driver CSVs in `dbt_project/seeds/`:

```csv
# allocation_drivers_headcount.csv
data_area_id,cost_center,driver_value,fiscal_year,fiscal_period
USMF,SALES,45,2024,1
USMF,OPS,30,2024,1
USMF,FINANCE,15,2024,1
```

The engine normalizes weights: `weight = driver_value / sum(driver_value)` per period, then distributes: `allocated = pool × weight`.

### Budgeting & Scenarios

#### Budget Spread Profiles (PRD-6)

Annual budgets are spread to 12 periods using configurable profiles.

Edit `dbt_project/seeds/spread_profiles.csv`:

```csv
profile_id,profile_name,fiscal_period,weight
EVEN,Even Spread,1,1.0
EVEN,Even Spread,2,1.0
...
SEASONAL,Retail Seasonal,11,1.8
SEASONAL,Retail Seasonal,12,2.5
```

Weights are auto-normalized. `EVEN` divides equally; `SEASONAL` gives heavier weight to peak months.

#### Budget Input

**Option A — CSV seed** (`dbt_project/seeds/budget_annual_input.csv`):
```csv
scenario_id,data_area_id,fiscal_year,main_account,dim_cost_center,dim_department,annual_amount,spread_profile_id,submitted_by
BUDGET_2025,USMF,2025,6100,SALES,REVENUE,1200000,EVEN,controller@co.com
BUDGET_2025,USMF,2025,7100,IT,OPEX,360000,SEASONAL,controller@co.com
```

**Option B — API**:
```bash
curl -X POST http://localhost:8080/api/v1/budget \
  -H "Content-Type: application/json" \
  -d '{"lines": [{"scenario_id": "BUDGET_2025", "legal_entity_id": "USMF",
       "fiscal_year": 2025, "fiscal_period": 1, "main_account": "6100",
       "dim_cost_center": "SALES", "amount": 100000, "submitted_by": "user@co.com"}]}'
```

**Option C — Streamlit** Scenario Manager page.

#### Variance Analysis (PRD-7)

Automatic actual vs budget comparison:
- `variance_abs = actual - budget`
- `variance_pct = variance_abs / |budget| × 100`
- Revenue: favorable when actual > budget
- Expense: favorable when actual < budget

### Configurable Dimensions

Dimensions are registry-driven via `dbt_project.yml` — add once, used everywhere:

```yaml
vars:
  dimensions:
    - name: dim_cost_center
      source_column: CostCenter
      label: "Cost Center"
      in_budget: true
      allocation_role: cost_center
    - name: dim_department
      source_column: Department
      label: "Department"
      in_budget: true
    - name: dim_business_unit
      source_column: BusinessUnit
      label: "Business Unit"
      in_budget: false
```

Macros (`dim_select()`, `dim_group_by()`, `dim_join_on()`) auto-generate SQL from this config. Adding a new dimension requires zero model changes — just add to the registry and re-run `dbt build`.

### Excel Integration

Excel connects to Cube's SQL API via PostgreSQL ODBC (port 15432):

1. Install PostgreSQL Unicode ODBC driver (64-bit)
2. Connection string: `Server=localhost; Port=15432; Database=epm_gold; Uid=epm_excel; Pwd=<password>`
3. Excel → Data → Get Data → From ODBC → Load tables → Insert PivotTable

**Available tables**: trial_balance, consolidated_tb, pnl, balance_sheet, variance, allocations, fx_revaluation, fully_consolidated

**Cell-level API** (for VBA/Power Query):
```
GET /api/v1/epm/value?entity=USMF&year=2024&period=1&account=6100&measure=period_net_amount
→ { "value": 850000.0 }
```

---

## Setup Guide

### Prerequisites

- Docker & Docker Compose
- Python 3.10+
- Git

### 1. Clone and Configure

```bash
git clone https://github.com/grynn-in/konsolidat.git
cd konsolidat
cp .env.example .env
# Edit .env with your D365 credentials and ClickHouse password
```

### 2. Start Infrastructure

```bash
docker compose up -d
```

This starts ClickHouse, Cube, Dagster, FastAPI, and Streamlit.

### 3. Install Airbyte

```bash
# Install abctl (Airbyte CLI)
curl -LsfS https://get.airbyte.com | bash -

# Start Airbyte
abctl local install

# Get credentials
abctl local credentials
```

Open http://localhost:8000, configure the D365 source with your OData credentials, and set ClickHouse as the destination.

### 4. Run dbt

```bash
cd dbt_project
pip install dbt-clickhouse
dbt deps
dbt seed    # Load allocation rules, consolidation groups, spread profiles
dbt build   # Build all models + run tests
```

### 5. Connect Excel

See the [Excel User Guide](docs/excel-user-guide.md) for ODBC setup and PivotTable configuration.

### 6. Verify

```bash
# Check dbt test results
dbt test

# Check API
curl http://localhost:8080/api/v1/health

# Check Cube
curl http://localhost:4000/readyz
```

---

## D365 OData Entities

The Airbyte connector syncs 14 OData entities from D365 F&O:

| Entity | Target Table | Sync Mode |
|--------|-------------|-----------|
| GeneralJournalAccountEntryBiEntities | GL line items | Incremental |
| GeneralJournalEntryBiEntities | GL journal headers | Incremental |
| MainAccounts | Chart of accounts | Full refresh |
| MainAccountCategories | Account categories | Full refresh |
| LegalEntities | Company master | Full refresh |
| Ledgers | Currency configuration | Full refresh |
| FiscalCalendarYears | Fiscal periods | Full refresh |
| DimensionAttributes | Dimension definitions | Full refresh |
| FinancialDimensionValues | Dimension values | Full refresh |
| ExchangeRates | FX rates | Incremental |
| ExchangeRateTypes | Rate type names | Full refresh |
| BudgetRegisterEntries | Budget headers + lines | Incremental |
| ConsolidateAccountGroups | Consolidation groups | Full refresh |
| TrialBalanceFiscalYearSnapshots | TB snapshots | Full refresh |

Staging models (`dbt_project/models/staging/stg_d365__*.sql`) handle all D365-specific transforms: field renames, JSON dimension parsing, rate scaling, entity joins, and deduplication.

---

## Project Structure

```
konsolidat/
├── source-d365-fno/           # Airbyte custom source connector (Python CDK)
│   ├── source_d365_fno/       # Connector code (auth, streams, schemas)
│   └── unit_tests/            # 28 unit tests
├── dbt_project/
│   ├── models/
│   │   ├── staging/           # 15 D365 transform views (raw → clean)
│   │   ├── bronze/            # 15 type-cast tables
│   │   ├── silver/            # Standardized trial balance, dimensions
│   │   └── gold/              # Consolidation, allocations, variance, budgets
│   ├── seeds/                 # CSV config: rules, groups, profiles, drivers
│   ├── macros/                # Allocation engine, dimension/measure helpers
│   └── tests/                 # Data quality assertions
├── cube/                      # Cube.js semantic layer (YAML schemas)
├── api/                       # FastAPI write-back (budget, scenarios)
├── streamlit/                 # Admin UI (rules, data quality, scenarios)
├── dagster/                   # Pipeline orchestration
├── docker/                    # Dockerfiles
├── scripts/                   # Utility scripts (OData sync, DB init)
├── docs/                      # PRDs, guides, architecture docs
└── docker-compose.yml
```

---

## Roadmap

- **Frappe App** — Replace FastAPI + Streamlit with a Frappe framework app for user management, permissions, workflow approvals, and Cube.js/ClickHouse proxy
- **Excel Online Add-in** — Browser-based Excel integration (replacing desktop ODBC)
- **Entra ID SSO** — Azure AD authentication via Frappe Social Login
- **Cash Flow Forecasting** — Direct/indirect method from GL data
- **Intercompany Matching** — Pre-elimination IC balance reconciliation
- **Audit Trail** — Full change tracking on consolidation adjustments and budget submissions

## Documentation

| Document | Description |
|----------|-------------|
| [Architecture](docs/architecture.md) | System design, ADRs, data flow |
| [Security Architecture](docs/security-architecture.md) | SSO, RBAC, Excel Online Add-in |
| [Cost Comparison](docs/cost-comparison-vs-commercial.md) | Konsol vs. Tagetik, OneStream, Planful |
| [Roadmap](docs/roadmap.md) | Remaining activities |
| [Setup Guide](docs/setup-guide.md) | Installation and configuration |
| [Consolidation Guide](docs/consolidation-guide.md) | Multi-entity consolidation, FX, IC elimination |
| [Allocation Guide](docs/allocation-guide.md) | Multi-step cascading allocations |
| [Excel User Guide](docs/excel-user-guide.md) | PivotTables, budget submission, ODBC setup |
| PRD-1 through PRD-7 | Feature specifications in `docs/prd/` |

## License

MIT
