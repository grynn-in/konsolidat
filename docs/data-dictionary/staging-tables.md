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
