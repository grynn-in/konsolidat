# Setup Guide

Complete deployment of Konsolidat: ClickHouse, Airbyte, dbt, Frappe/Konsol, and the Excel add-in.

## Prerequisites

| Component | Version | Purpose |
|-----------|---------|---------|
| Docker Desktop | 24+ | ClickHouse container |
| Python | 3.10+ | dbt Core, Frappe Bench |
| Node.js | 18+ | Frappe assets |
| Excel | Microsoft 365 or 2021+, desktop or web | Add-in reporting |
| D365 F&O | Any | Source ERP (optional for demo) |

## 1. Clone the Repository

```bash
git clone https://github.com/your-org/konsolidat.git
cd konsolidat
cp .env.example .env
```

Edit `.env` to set your ClickHouse password:

```
CLICKHOUSE_PASSWORD=your_secure_password
```

## 2. Start ClickHouse

```bash
docker compose up -d
```

This starts a single ClickHouse container with:
- HTTP API on port **8123**
- Native protocol on port **9000**
- PostgreSQL wire protocol on port **15432**
- Init SQL creates databases: `epm_bronze`, `epm_staging`, `epm_silver`, `epm_gold`

Verify:

```bash
curl "http://localhost:8123/?query=SHOW+DATABASES"
```

## 3. Set Up Airbyte (D365 Extraction)

> Skip this section if using seed data only (demo mode).

### 3.1 Install Airbyte

```bash
curl -fsSL https://get.airbyte.com | bash    # Installs abctl
abctl local install
```

Airbyte UI will be available at `http://localhost:8000`.

### 3.2 Register a D365 App in Azure AD

1. Go to [Azure Portal → App Registrations](https://portal.azure.com/#blade/Microsoft_AAD_RegisteredApps/ApplicationsListBlade)
2. **New registration** → name: `Konsolidat Airbyte`
3. Under **API permissions** → Add: `Dynamics 365 Finance and Operations → Ax.FullAccess`
4. Under **Certificates & secrets** → New client secret → copy the value
5. Note: `Tenant ID`, `Client ID`, `Client Secret`, `D365 Environment URL`

### 3.3 Configure Airbyte Connection

**Source**: Dynamics 365 Finance & Operations (OData)
- Tenant ID, Client ID, Client Secret, Environment URL from step 3.2
- Enable `cross_company=true` on all streams

**Destination**: ClickHouse
- Host: `host.docker.internal` (Docker-to-host), Port: `8123`
- Database: `epm_bronze`, User: `default`, Password: from `.env`

**Streams** (15 entities):

| OData Entity | Bronze Table |
|-------------|-------------|
| `GeneralJournalAccountEntries` | `bronze_general_journal_account_entries` |
| `GeneralJournalEntries` | `bronze_general_journal_entries` |
| `MainAccounts` | `bronze_main_accounts` |
| `MainAccountCategories` | `bronze_main_account_categories` |
| `LegalEntities` | `bronze_legal_entities` |
| `FiscalCalendars` | `bronze_fiscal_calendars` |
| `FiscalCalendarYears` | `bronze_fiscal_calendar_years` |
| `FinancialDimensions` | `bronze_financial_dimensions` |
| `FinancialDimensionValues` | `bronze_financial_dimension_values` |
| `ExchangeRateCurrencyPairs` | `bronze_exchange_rate_currency_pairs` |
| `ExchangeRateTypes` | `bronze_exchange_rate_types` |
| `BudgetRegisterEntries` | `bronze_budget_register_entries` |
| `BudgetTransactionLines` | `bronze_budget_transaction_lines` |
| `ConsolidationAccountGroups` | `bronze_consolidation_account_groups` |
| `LedgerTrialBalanceFiscalYearSnapshotDataEntity` | `bronze_trial_balance_snapshot` |

### 3.4 Run Initial Sync

Trigger a full sync from the Airbyte UI or CLI. This populates `epm_bronze` tables.

## 4. Install and Run dbt

```bash
cd dbt_project
pip install dbt-core dbt-clickhouse
```

Create `~/.dbt/profiles.yml` (if not present):

```yaml
konsolidat:
  target: dev
  outputs:
    dev:
      type: clickhouse
      host: localhost
      port: 8123
      user: default
      password: "your_password"
      schema: epm_gold
      secure: false
```

Build:

```bash
dbt deps       # Install dbt packages
dbt seed       # Load 11 CSV seeds into epm_gold schema
dbt build      # Build all models + run 26 tests
```

### Seed Files (11)

| Seed | Purpose |
|------|---------|
| `allocation_rules.csv` | 3 multi-step allocation rules |
| `allocation_drivers_headcount.csv` | Headcount driver values |
| `allocation_drivers_sqm.csv` | Square meter driver values |
| `allocation_drivers_revenue.csv` | Revenue driver values |
| `budget_annual_input.csv` | Annual budget line items |
| `spread_profiles.csv` | Monthly spread weights (EVEN, SEASONAL_RETAIL) |
| `consolidation_groups.csv` | Entity → group mapping with ownership % |
| `consolidation_adjustments.csv` | Top-side journal entries |
| `ic_elimination_rules.csv` | Intercompany elimination rules |
| `scenario_definitions.csv` | Scenario metadata (actuals, budget, forecast) |
| `entity_fiscal_calendars.csv` | Entity → fiscal calendar mapping |

## 5. Set Up Frappe / Konsol

### 5.1 Install Frappe Bench

```bash
pip install frappe-bench
bench init frappe-bench --frappe-branch version-15
cd frappe-bench
```

### 5.2 Install Konsol App

```bash
bench get-app /path/to/konsol    # Or git URL
bench new-site konsolidat.local --db-type mariadb --admin-password admin
bench --site konsolidat.local install-app konsol
bench start
```

Frappe is now running at `http://localhost:8069`.

### 5.3 Configure EPM Settings

1. Log in to Frappe Desk (`http://localhost:8069`)
2. Navigate to **Setup → EPM Settings**
3. Fill in:

| Field | Value |
|-------|-------|
| ClickHouse Host | `localhost` |
| ClickHouse Port | `8123` |
| ClickHouse User | `default` |
| ClickHouse Password | Your `.env` password |
| Airbyte API URL | `http://localhost:8000` |
| Airbyte Connection ID | From Airbyte UI |
| dbt Project Path | `/path/to/konsolidat/dbt_project` |

4. Save

## 6. Install the Excel Add-in

The konsol Office add-in provides the `K.` worksheet functions and the Konsolidat task pane (pipeline control).

### 6.1 Sideload for Development

1. Take `konsol/public/excel-addin/manifest.xml` from the konsol repository
2. In Excel: **Insert → My Add-ins → Upload My Add-in** → select the manifest
3. The **Konsolidat** button appears on the Home tab

### 6.2 Sign In and Test

1. Open the Konsolidat task pane and sign in with your Frappe credentials
2. In any cell: `=K.EPM("USMF", 2024, 5, "401100")`

The task pane connects to Frappe at `http://localhost:8069` and also lets you view the latest pipeline run and trigger a new one (Airbyte sync + dbt build).

## Verification Checklist

- [ ] `docker ps` shows `konsolidat_clickhouse` healthy
- [ ] `curl http://localhost:8123/?query=SHOW+DATABASES` returns 4 databases
- [ ] `dbt build` completes with 0 errors
- [ ] Frappe Desk accessible at `http://localhost:8069`
- [ ] EPM Settings saved with ClickHouse connection
- [ ] `=K.EPM("USMF", 2024, 5, "401100")` returns a numeric value

## Next Steps

- [Configuration Reference](configuration-reference.md) — All settings in detail
- [Excel Formulas Guide](../user-guide/excel-formulas-guide.md) — Building reports with `K.EPM` formulas
- [D365 Integration](../admin-guide/d365-integration.md) — Azure AD, OData entity details
- [Deployment Guide](../admin-guide/deployment-guide.md) — Production deployment
