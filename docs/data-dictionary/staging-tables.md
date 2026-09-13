# Staging Tables

The `epm_staging` database contains intermediate views used by the dbt staging layer, and write-back tables for user-submitted data. konsol also writes governed reference tables and uploaded trial balances (`epm_raw.trial_balance_submissions`) into ClickHouse; see [Tables konsol Writes](#tables-konsol-writes).

## Staging Views

Staging models are materialized as **views** in the `epm_staging` schema. They perform field renames, joins, and JSON parsing without persisting data.

Staging models sit between Bronze (raw) and Silver (cleaned) layers:

```
epm_bronze (Airbyte tables) → epm_staging (views) → epm_silver (tables)
```

Each staging view typically:
1. Selects from the corresponding Bronze table
2. Renames fields from PascalCase to snake_case
3. Casts types using `db_adapter.sql` macros
4. Joins related reference tables (e.g., journal headers to line items)

Staging views are not directly queried by the API or Excel — they're internal to the dbt pipeline.

## Write-Back Tables (Planned)

The `epm_staging` database is also reserved for future write-back scenarios:

| Table | Purpose | Status |
|-------|---------|--------|
| `staging_budget_submissions` | Budget entries submitted from Excel | Planned |
| `staging_consolidation_adjustments` | Top-side journals submitted via UI | Planned |

The planned workflow:
1. User submits data from Excel or Frappe UI
2. Data lands in `epm_staging` table
3. Approval workflow in Frappe
4. Approved data is picked up by dbt on next build

## Tables konsol Writes

konsol writes governed reference data and trial balance uploads straight into ClickHouse. `clickhouse/init-db.sql` creates these tables on a fresh volume, and konsol creates them (with the same definitions) on migrate. The entries below are the ones consolidation's exchange rates and intercompany matching read.

### epm_staging.group_exchange_rates

The group's approved exchange rates (konsol **Group Exchange Rate**, konsol #174). One row per approved rate; konsol replaces the whole set at once on every approval or cancellation. `gold_consolidated_trial_balance` translates from this table only.

| Column | Type | Description |
|--------|------|-------------|
| `to_currency` | String | The group's reporting currency |
| `from_currency` | String | The entity currency being translated |
| `fiscal_year` | UInt16 | Fiscal year |
| `fiscal_period` | UInt8 | Fiscal period (0 = OPN, 1–12, 13 = CLS) |
| `rate_type` | String | `Closing` or `Average` |
| `rate` | Float64 | The **true rate**: units of `to_currency` per 1 unit of `from_currency` (konsol's Quote ÷ Quoted Per). Used as published; never scaled or inverted |
| `document` | String | The Group Exchange Rate document name |

Sort key: `(to_currency, from_currency, fiscal_year, fiscal_period, rate_type)`. See the [Exchange Rates Guide](../user-guide/exchange-rates-guide.md).

### epm_staging.intercompany_accounts

The intercompany flag on the group chart (konsol **Intercompany Account**, konsol #159). Only Published rows are written.

| Column | Type | Description |
|--------|------|-------------|
| `main_account` | String | An intercompany account |
| `counterpart_account` | String | The account the partner books the other side on; `''` when both sides use `main_account` |
| `description` | String | Free text |
| `status` | String | `Published` |

Read by `gold_ic_reconciliation` and `gold_ic_unmatched`. See the [Intercompany Guide](../user-guide/intercompany-guide.md).

### epm_gold.currencies

The ISO 4217 list, written from konsol's **ISO Currency**.

| Column | Type | Description |
|--------|------|-------------|
| `currency_code` | String | ISO code |
| `currency_name` | String | Name |
| `symbol` | String | Symbol |
| `minor_unit` | UInt8 | Decimal places |
| `usd_log10` | Float64, default `nan` | **USD Reference (log10)**: roughly log10 of the currency's units per 1 USD. The magnitude check refuses a rate more than 10× from what two references imply. No reference = `nan`, or 0 for any currency other than USD |

### epm_raw.trial_balance_submissions

The rows of submitted trial balances (single Trial Balance Submission and bulk uploads). Rows count only once their batch is claimed in `epm_raw.trial_balance_submission_control`.

| Column | Type | Description |
|--------|------|-------------|
| `batch_id` | String | The submission's batch |
| `data_area_id` | String | Entity |
| `fiscal_year` | UInt16 | Fiscal year |
| `fiscal_period` | UInt8 | Fiscal period |
| `main_account` | String | Account |
| `debit_amount`, `credit_amount` | Float64 | Positive amounts in the entity's own currency |
| `description` | String | Row description |
| `submission_name`, `submitted_at` | String, DateTime | The Trial Balance Submission and when it was submitted |
| `partner_data_area_id` | String, default `''` | The intercompany partner entity (konsol #159); `''` when the row has none |

## ClickHouse Databases

Created by `clickhouse/init-db.sql`:

```sql
CREATE DATABASE IF NOT EXISTS epm_bronze;
CREATE DATABASE IF NOT EXISTS epm_staging;
CREATE DATABASE IF NOT EXISTS epm_silver;
CREATE DATABASE IF NOT EXISTS epm_gold;
```

| Database | Managed By | Contents |
|----------|-----------|----------|
| `epm_bronze` | Airbyte | Raw D365 OData tables |
| `epm_staging` | dbt | Staging views + write-back tables |
| `epm_silver` | dbt | Cleaned, standardized tables |
| `epm_gold` | dbt, konsol | Business logic; a few konsol-written reference tables (e.g. `consolidation_groups`, `scenario_definitions`) |
