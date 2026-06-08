# Adding Dimensions

Konsolidat's dimension system is defined once in `dbt_project.yml` and auto-propagates through all Gold models via Jinja macros.

## How It Works

### 1. Define in dbt_project.yml

```yaml
vars:
  dimensions:
    - name: dim_cost_center        # Column name in Gold models
      source_column: CostCenter    # D365 OData field name
      label: "Cost Center"         # Display name
      cube_type: string            # Analytical type
      in_budget: true              # Include in budget models
      allocation_role: cost_center # Used by allocation engine
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

### 2. Macros Read the Config

The `dimension_helpers.sql` macros read `var('dimensions')` and generate SQL fragments:

```sql
-- In a Gold model:
select
    data_area_id,
    {{ dim_select('gl.') }},         -- gl.dim_cost_center, gl.dim_department, gl.dim_business_unit
    {{ measure_select() }}
from {{ ref('silver_gl_entries') }} as gl
group by
    data_area_id,
    {{ dim_group_by('gl.') }}        -- gl.dim_cost_center, gl.dim_department, gl.dim_business_unit
```

### 3. API Filters Automatically

The Frappe API's `_batch_query_clickhouse()` function accepts `cost_center` and `department` as optional filters. These map to `dim_cost_center` and `dim_department` in the SQL `WHERE` clause.

## Adding a New Dimension

### Step 1: Add to dbt_project.yml

```yaml
vars:
  dimensions:
    # ... existing dimensions ...
    - name: dim_project
      source_column: Project
      label: "Project"
      cube_type: string
      in_budget: false
```

### Step 2: Verify Source Data

Ensure the D365 OData entity exposes the field. Check the Bronze model:

```sql
select distinct Project from epm_bronze.bronze_general_journal_account_entries limit 10
```

### Step 3: Rebuild

```bash
dbt build --full-refresh
```

The dimension macros will automatically include `dim_project` in all models that use `dim_select()`, `dim_group_by()`, etc.

### Step 4: Update API (Optional)

If you want the new dimension to be filterable via `=EPM()`:

1. Add a parameter to `epm_value()` and `epm_batch()` in `konsol/api.py`
2. Add it to the SQL WHERE clause generation in `_batch_query_clickhouse()`
3. Add it to the VBA `ResolveEpmArgs()` function if needed

## Dimension Properties

| Property | Required | Description |
|----------|----------|-------------|
| `name` | Yes | Column name in Gold models (convention: `dim_*`) |
| `source_column` | Yes | Field name in D365 OData / Bronze source |
| `label` | Yes | Human-readable display name |
| `cube_type` | Yes | Analytical type (currently: `string`) |
| `in_budget` | Yes | `true` to include in budget models (`get_budget_dimensions()`) |
| `allocation_role` | No | Special role: `cost_center` is used by the allocation engine |

## Which Macros Use Dimensions

| Macro | Where Used | Effect |
|-------|-----------|--------|
| `dim_select()` | SELECT clauses | Adds dimension columns |
| `dim_group_by()` | GROUP BY clauses | Groups by dimensions |
| `dim_join_on()` | JOIN conditions | Matches dimensions across tables |
| `dim_coalesce()` | FULL OUTER JOIN results | Picks non-null dimension value |
| `dim_partition_by()` | Window functions | Partitions by dimensions |
| `dim_empty_strings()` | Non-entity consolidation layers | Fills `''` for IC/CTA rows |
| `dim_select_from_source()` | Bronze models | Maps OData source_column to dim_name |

## Budget Dimensions

`get_budget_dimensions()` filters to dimensions with `in_budget: true`. These are the only dimensions included in the budget spread model. Currently:

- `dim_cost_center` (in_budget: true)
- `dim_department` (in_budget: true)
- `dim_business_unit` (in_budget: false — excluded from budget)

Set `in_budget: true` on your new dimension if budget data should be tracked at that level.

## Allocation Cost Center Dimension

`get_allocation_cost_center_dim()` returns the dimension with `allocation_role: 'cost_center'`. The allocation engine uses this to match source/target cost centers. Only one dimension should have this role.

## Next Steps

- [Macro Reference](macro-reference.md) — Full dimension macro signatures
- [Extending dbt Models](extending-dbt-models.md) — Using dimensions in new models
- [Configuration Reference](../getting-started/configuration-reference.md) — All dbt_project.yml vars
