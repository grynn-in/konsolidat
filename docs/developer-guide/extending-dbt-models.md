# Extending dbt Models

Step-by-step guide to adding a new Gold model to Konsolidat.

## Adding a Gold dbt Model

### 1. Create the SQL File

Create `dbt_project/models/gold/gold_your_model.sql`:

```sql
{{
    config(
        materialized='table',
        tags=['gold'],
        **epm_config(order_by='(data_area_id, fiscal_year, fiscal_period, main_account)')
    )
}}

select
    tb.data_area_id,
    tb.fiscal_year,
    tb.fiscal_period,
    tb.main_account,
    {{ dim_select('tb.') }},
    {{ measure_passthrough('tb.') }}
from {{ ref('gold_trial_balance') }} as tb
where tb.fiscal_period between 1 and 12
```

Key points:
- Use `epm_config()` for ClickHouse engine settings
- Use `dim_select()` / `dim_group_by()` for dimension columns
- Use `measure_passthrough()` for standard measures
- Reference upstream models with `{{ ref('model_name') }}`

### 2. Add YAML Documentation

Add an entry to `dbt_project/models/gold/_gold__models.yml`:

```yaml
  - name: gold_your_model
    description: "What this model does"
    columns:
      - name: data_area_id
        description: "Legal entity identifier"
        tests:
          - not_null
      - name: your_key_column
        description: "Description of this column"
```

### 3. Add Tests

Create `dbt_project/tests/assert_your_condition.sql`:

```sql
-- Describe what this test checks
select *
from {{ ref('gold_your_model') }}
where some_condition_that_should_never_be_true
```

dbt tests return rows that **violate** the assertion. Zero rows = pass.

Use `{{ config(severity='warn') }}` for non-blocking tests.

### 4. Build and Test

```bash
dbt run --select gold_your_model    # Build just this model
dbt test --select gold_your_model   # Run tests
dbt build --select gold_your_model  # Both in one command
```

### 5. Register for Governed Builds

Register the model as a konsol **Build Model** doc, assigning its **Build Scope** — this generates the model's `domain:<scope>` tag in `dbt_project.yml` so scoped governed builds select it. A gold model with no scope is only built by a full build; `scripts/check_gold_domains.py` fails CI for untagged gold models.

## Adding a Seed-Driven Model

If your model needs reference data:

### 1. Create the Seed CSV

Add `dbt_project/seeds/your_reference_data.csv`:

```csv
column_a,column_b,column_c
value1,value2,value3
```

### 2. Configure Column Types (Optional)

In `dbt_project.yml`, add type overrides:

```yaml
seeds:
  konsolidat:
    your_reference_data:
      +column_types:
        column_a: String
        column_b: Decimal(18,2)
```

### 3. Reference in Your Model

```sql
from {{ ref('your_reference_data') }} as ref_data
```

### 4. Load the Seed

```bash
dbt seed --select your_reference_data
```

## Patterns to Follow

### Aggregation Model

```sql
select
    data_area_id,
    fiscal_year,
    fiscal_quarter,
    main_account,
    {{ dim_select() }},
    sum(period_net_amount) as quarter_net_amount
from {{ ref('gold_trial_balance') }} as tb
inner join {{ ref('gold_period_hierarchy') }} as ph
    on tb.fiscal_period = ph.fiscal_period
group by
    data_area_id,
    fiscal_year,
    fiscal_quarter,
    main_account,
    {{ dim_group_by() }}
```

### Join Model (e.g., Variance)

```sql
select
    {{ dim_coalesce('a', 'b') }},
    a.amount as actual_amount,
    b.amount as budget_amount,
    a.amount - b.amount as variance_abs
from {{ ref('gold_trial_balance') }} as a
full outer join {{ ref('gold_spread_budget') }} as b
    on a.data_area_id = b.data_area_id
    and a.fiscal_year = b.fiscal_year
    and a.fiscal_period = b.fiscal_period
    and a.main_account = b.main_account
    {{ dim_join_on('a', 'b') }}
```

### Window Function Model (e.g., YTD)

```sql
select
    *,
    sum(period_net_amount) over (
        partition by data_area_id, fiscal_year, main_account,
        {{ dim_partition_by() }}
        order by fiscal_period
    ) as ytd_net_amount
from {{ ref('gold_trial_balance') }}
```

### Consolidation Layer (Empty Dims)

For non-entity layers (IC, CTA), use `dim_empty_strings()`:

```sql
select
    consolidation_group,
    'ic_elimination' as adjustment_type,
    '' as data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    {{ dim_empty_strings() }},
    elimination_amount as amount
from {{ ref('gold_ic_eliminations') }}
```

## Making a Model API-Queryable

To expose a new model through the `=EPM()` function, register it in the **Dataset** registry (Frappe Desk → Dataset) — no code change needed:

1. Create a Dataset with `clickhouse_table` pointing at the model's table
2. Add its allowed measures and dimensions (Dataset Measure / Dataset Dimension child rows)
3. Publish the Dataset — the API resolves `fact` / `scenario` through the registry

See [Extending the API](extending-api.md) for details.

## Next Steps

- [Adding Dimensions](adding-dimensions.md) — How the dimension system works
- [Testing Guide](testing-guide.md) — Writing comprehensive tests
- [Macro Reference](macro-reference.md) — All available macros
