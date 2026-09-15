# Staging Tables

The `epm_staging` database contains intermediate views used by the dbt staging layer, and write-back tables for user-submitted data.

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

## Deal Tables (konsol writes, dbt reads)

konsolidat#198: konsol syncs its **submitted** Business Combination and Business
Disposal documents into six `epm_staging` tables (DDL in `clickhouse/init-db.sql`,
pinned verbatim by `tests/test_deal_tables_ddl.py`, declared as sources in
`dbt_project/models/staging/_staging__sources.yml`). The three deal journals read
them; see [Business Combinations](../developer-guide/design/business-combinations.md).
Amounts in the header Result columns are group currency as konsol computed them;
child-table amounts are in their own `currency` (acquired balances: the entity's
accounting currency, Dr positive / Cr negative).

| Table | Grain | Columns |
|-------|-------|---------|
| `business_combinations` | one row per deal (`name`) | `consolidation_group, acquired_entity, acquisition_date, share_acquired_pct, consideration_currency, total_consideration, net_assets_acquired, fair_value_adjustments, goodwill, bargain_purchase_gain, nci_at_acquisition, ownership_period, nci_measurement, nci_fair_value` |
| `business_combination_consideration` | `(parent, idx)` | `component, amount, currency, settlement_date, description` |
| `business_combination_acquired_balances` | `(parent, idx)` | `main_account, book_amount, fair_value_adjustment, note` (empty when konsol measured from the TB) |
| `business_combination_costs` | `(parent, idx)` | `kind, amount, currency, description` |
| `business_disposals` | one row per disposal (`name`) | `consolidation_group, disposed_entity, disposal_date, share_disposed_pct, retained_interest_pct, proceeds_currency, total_proceeds, ownership_period` |
| `business_disposal_proceeds` | `(parent, idx)` | `component, amount, currency, settlement_date, description` |

`business_combinations.nci_measurement` (`String DEFAULT ''`, `'partial'` | `'full'`)
is the NCI measurement in force for the deal: its override or the group's
(konsol#205); the acquisition journal reads this, not the group's value.
`business_combinations.nci_fair_value` (`Float64 DEFAULT 0`) is the minority's own
acquisition-date fair value in the deal's `consideration_currency`, declared when the
deal measures NCI at `full` (konsol#204); the journal posts it as the NCI instead of
grossing up the consideration.

The declared accounts and the Consolidation Policy the journals post with live on the
root row (`data_area_id = ''`) of `epm_gold.consolidation_groups`: `nci_measurement,
accounting_framework, framework_note, goodwill_treatment, goodwill_amortisation_years,
acquisition_costs_treatment, measurement_period, bargain_purchase` and the nine
`*_account` columns.

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
| `epm_gold` | dbt | Business logic + seed tables |
