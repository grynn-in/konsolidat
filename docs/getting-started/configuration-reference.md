# Configuration Reference

All configuration surfaces in Open EPM, from environment variables to dbt project settings to Excel workbook properties.

## Environment Variables (`.env`)

Used by `docker-compose.yml` and can be overridden at runtime.

| Variable | Default | Description |
|----------|---------|-------------|
| `CLICKHOUSE_USER` | `default` | ClickHouse login user |
| `CLICKHOUSE_PASSWORD` | `open_epm_dev` | ClickHouse login password |

## Frappe EPM Settings

A Single DocType at **Setup → EPM Settings** in the Frappe Desk UI. Stores connection details read by `konsol.api` at runtime.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `clickhouse_host` | Data | `localhost` | ClickHouse server hostname |
| `clickhouse_port` | Data | `8123` | ClickHouse HTTP port |
| `clickhouse_user` | Data | `default` | ClickHouse user for API queries |
| `clickhouse_password` | Password | — | ClickHouse password |
| `airbyte_api_url` | Data | `http://localhost:8000` | Airbyte API base URL |
| `airbyte_connection_id` | Data | — | Airbyte connection UUID for D365 sync |
| `airbyte_client_id` | Data | — | Airbyte API client ID |
| `airbyte_client_secret` | Password | — | Airbyte API client secret |
| `dbt_project_path` | Data | `/home/pd/open_epm/dbt_project` | Absolute path to dbt project directory |

**Permission**: System Manager role (read/write/create).

## dbt Project Variables (`dbt_project.yml`)

### `dimensions`

A list of dimension definitions that auto-propagate through all Gold models via dimension helper macros.

```yaml
vars:
  dimensions:
    - name: dim_cost_center
      source_column: CostCenter       # D365 OData field name
      label: "Cost Center"
      cube_type: string
      in_budget: true                  # Include in budget models
      allocation_role: cost_center     # Used by allocation engine
    - name: dim_department
      source_column: Department
      label: "Department"
      cube_type: string
      in_budget: true
    - name: dim_business_unit
      source_column: BusinessUnit
      label: "Business Unit"
      cube_type: string
      in_budget: false
```

### `base_measures`

Aggregate expressions applied in `gold_trial_balance`. Referenced by `measure_select()` and `measure_passthrough()` macros.

```yaml
vars:
  base_measures:
    - name: period_debit
      expression: "sum(debit_amount)"
      label: "Debit"
      cube_type: sum
    - name: period_credit
      expression: "sum(credit_amount)"
      label: "Credit"
      cube_type: sum
    - name: period_net_amount
      expression: "sum(accounting_currency_amount)"
      label: "Net Amount"
      cube_type: sum
    - name: transaction_count
      expression: "count(*)"
      label: "Transaction Count"
      cube_type: sum
```

### `fiscal_extra_periods`

Special fiscal periods beyond the standard 1–12.

```yaml
vars:
  fiscal_extra_periods:
    - { period: 0,  label: OPN, quarter: OPN, half: OPN }
    - { period: 13, label: CLS, quarter: CLS, half: CLS }
```

### `fiscal_quarter_mapping` / `fiscal_half_mapping`

Maps fiscal period numbers to quarter/half labels. Calendar-aligned by default.

```yaml
vars:
  fiscal_quarter_mapping:
    1: Q1
    2: Q1
    3: Q1
    4: Q2
    # ... through 12: Q4
  fiscal_half_mapping:
    1: H1
    2: H1
    # ... 6: H1, 7: H2 ... 12: H2
```

### Model Materialization

| Layer | Schema | Materialization | Tags |
|-------|--------|----------------|------|
| staging | `staging` | view | staging |
| bronze | `bronze` | table | bronze |
| silver | `silver` | table | silver |
| gold | `gold` | table | gold |

### Seed Column Types

Custom column types are specified per seed in `dbt_project.yml`:

- **`consolidation_groups`**: `ownership_pct` → `Decimal(5,2)`
- **`consolidation_adjustments`**: All columns typed — `consolidation_group` (String), `fiscal_year` (UInt16), `fiscal_period` (UInt8), `debit_amount` / `credit_amount` (Decimal(18,2)), etc.

## Excel VBA Configuration

### `EPM_API_URL` (Custom Document Property)

The VBA module reads the API base URL from a workbook-level Custom Document Property named `EPM_API_URL`.

| Property | Type | Default | Set By |
|----------|------|---------|--------|
| `EPM_API_URL` | String | `http://localhost:8069` | `EPM_SetServer` macro |

To set programmatically: run `EPM_SetServer` from the Excel macro menu, or set via VBA:

```vba
ActiveWorkbook.CustomDocumentProperties.Add _
    Name:="EPM_API_URL", _
    LinkToContent:=False, _
    Type:=msoPropertyTypeString, _
    Value:="https://your-frappe-server.com"
```

### VBA Module Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `DEFAULT_API_URL` | `http://localhost:8069` | Fallback when no Custom Document Property is set |
| `LOG_SHEET_NAME` | `_EPM_Log` | Hidden sheet for debug logging |

## ClickHouse Databases

Created by `clickhouse/init-db.sql` on first startup:

| Database | Purpose |
|----------|---------|
| `epm_bronze` | Airbyte-managed raw tables |
| `epm_staging` | dbt staging views |
| `epm_silver` | dbt silver tables |
| `epm_gold` | dbt gold tables (consumed by API) |

## Docker Compose Services

| Service | Image | Ports |
|---------|-------|-------|
| `clickhouse` | `clickhouse/clickhouse-server:24.8-alpine` | 8123 (HTTP), 9000 (native), 15432 (PostgreSQL wire) |

Volumes: `clickhouse_data`, `clickhouse_logs`
Health check: `clickhouse-client --query "SELECT 1"` every 10s.

## D365 Airbyte Connection

15 OData entities extracted with `cross_company=true`:

`GeneralJournalAccountEntries`, `GeneralJournalEntries`, `MainAccounts`, `MainAccountCategories`, `LegalEntities`, `FiscalCalendars`, `FiscalCalendarYears`, `FinancialDimensions`, `FinancialDimensionValues`, `ExchangeRateCurrencyPairs`, `ExchangeRateTypes`, `BudgetRegisterEntries`, `BudgetTransactionLines`, `ConsolidationAccountGroups`, `LedgerTrialBalanceFiscalYearSnapshotDataEntity`

Destination: ClickHouse at `host.docker.internal:8123`, database `epm_bronze`.
