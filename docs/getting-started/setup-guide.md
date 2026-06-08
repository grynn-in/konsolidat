# Setup Guide

Complete deployment of Open EPM: ClickHouse, Airbyte, dbt, Frappe/Konsol, and Excel VBA.

## Prerequisites

| Component | Version | Purpose |
|-----------|---------|---------|
| Docker Desktop | 24+ | ClickHouse container |
| Python | 3.10+ | dbt Core, Frappe Bench |
| Node.js | 18+ | Frappe assets |
| Excel | 2016+ | VBA reporting |
| D365 F&O | Any | Source ERP (optional for demo) |

## 1. Clone the Repository

```bash
git clone https://github.com/your-org/open_epm.git
cd open_epm
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
2. **New registration** → name: `Open EPM Airbyte`
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
open_epm:
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
bench new-site open-epm.local --db-type mariadb --admin-password admin
bench --site open-epm.local install-app konsol
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
| dbt Project Path | `/path/to/open_epm/dbt_project` |

4. Save

## 6. Set Up Excel VBA

### 6.1 Import the VBA Module

1. Open Excel → **Alt+F11** (VBA Editor)
2. **File → Import File** → `excel/OpenEPM.bas`
3. Close VBA Editor
4. Save workbook as `.xlsm`

### 6.2 Add References (Required)

In the VBA Editor: **Tools → References** → check:
- `Microsoft Scripting Runtime` (for `Scripting.Dictionary`)
- `Microsoft XML, v6.0` (for `MSXML2.XMLHTTP60`)

### 6.3 Configure Server URL

Run `EPM_SetServer` macro (Alt+F8) and enter your Frappe URL (e.g., `http://localhost:8069`).

This saves the URL as a Custom Document Property in the workbook, so it persists across sessions.

### 6.4 Log In and Test

1. Run `EPM_Login` → enter Frappe credentials
2. In any cell: `=EPM("USMF", 2024, 5, "401100")`
3. Press **Ctrl+Shift+R** to refresh

## 7. Optional: Excel Task Pane Add-in

The Office.js task pane provides pipeline orchestration (trigger sync + dbt from Excel).

### Sideload for Development

1. Copy `excel-addin/manifest.xml`
2. In Excel: **Insert → My Add-ins → Upload My Add-in** → select the manifest
3. The task pane appears on the Home tab as "Open EPM"

The task pane connects to Frappe at `http://localhost:8069` and allows:
- Login with Frappe credentials
- Viewing latest pipeline run status
- Triggering new pipeline runs (Airbyte sync + dbt build)

## Verification Checklist

- [ ] `docker ps` shows `open_epm_clickhouse` healthy
- [ ] `curl http://localhost:8123/?query=SHOW+DATABASES` returns 4 databases
- [ ] `dbt build` completes with 0 errors
- [ ] Frappe Desk accessible at `http://localhost:8069`
- [ ] EPM Settings saved with ClickHouse connection
- [ ] `=EPM("USMF", 2024, 5, "401100")` returns a numeric value after Ctrl+Shift+R

## Next Steps

- [Configuration Reference](configuration-reference.md) — All settings in detail
- [Excel VBA Guide](../user-guide/excel-vba-guide.md) — Building reports with EPM formulas
- [D365 Integration](../admin-guide/d365-integration.md) — Azure AD, OData entity details
- [Deployment Guide](../admin-guide/deployment-guide.md) — Production deployment
