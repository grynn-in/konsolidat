# Macro Reference

All dbt macros in Konsolidat, organized by file.

## dimension_helpers.sql

Macros driven by `var('dimensions')` in `dbt_project.yml`. Each dimension is a dict with keys: `name`, `source_column`, `label`, `cube_type`, `in_budget`, `allocation_role`.

### get_dimensions()

Returns the full `var('dimensions')` list.

```sql
{% set dims = get_dimensions() %}
{# Returns: [{name: 'dim_cost_center', source_column: 'CostCenter', ...}, ...] #}
```

### get_budget_dimensions()

Returns only dimensions where `in_budget: true`.

```sql
{% set budget_dims = get_budget_dimensions() %}
{# Returns dims for dim_cost_center and dim_department (not dim_business_unit) #}
```

### get_allocation_cost_center_dim()

Returns the `name` of the dimension with `allocation_role: 'cost_center'`. Falls back to `'dim_cost_center'`.

```sql
{% set cc_dim = get_allocation_cost_center_dim() %}
{# Returns: 'dim_cost_center' #}
```

### dim_select(prefix='', dims=none)

Generates a comma-separated SELECT list of dimension columns.

```sql
select {{ dim_select('gl.') }}
-- Output: gl.dim_cost_center, gl.dim_department, gl.dim_business_unit
```

### dim_group_by(prefix='', dims=none)

Generates a comma-separated GROUP BY list.

```sql
group by {{ dim_group_by('gl.') }}
-- Output: gl.dim_cost_center, gl.dim_department, gl.dim_business_unit
```

### dim_join_on(left, right, dims=none)

Generates `AND` join conditions for all dimensions.

```sql
on a.data_area_id = b.data_area_id
{{ dim_join_on('a', 'b') }}
-- Output: and a.dim_cost_center = b.dim_cost_center
--         and a.dim_department = b.dim_department
--         and a.dim_business_unit = b.dim_business_unit
```

### dim_coalesce(left, right, dims=none)

Generates `COALESCE` expressions for FULL OUTER JOIN results.

```sql
select {{ dim_coalesce('a', 'b') }}
-- Output: coalesce(a.dim_cost_center, b.dim_cost_center) as dim_cost_center,
--         coalesce(a.dim_department, b.dim_department) as dim_department, ...
```

### dim_partition_by(prefix='', dims=none)

Generates a PARTITION BY clause for window functions.

```sql
sum(amount) over (partition by {{ dim_partition_by('t.') }})
-- Output: t.dim_cost_center, t.dim_department, t.dim_business_unit
```

### dim_empty_strings(dims=none)

Generates `'' AS dim_name` for layers that don't have dimension data (IC eliminations, CTA, etc.).

```sql
select {{ dim_empty_strings() }}
-- Output: '' as dim_cost_center, '' as dim_department, '' as dim_business_unit
```

### dim_select_from_source(prefix='', dims=none)

Maps source columns (D365 OData names) to dimension columns with null-safe casting.

```sql
select {{ dim_select_from_source('raw.') }}
-- Output: toString(assumeNotNull(coalesce(raw.CostCenter, ''))) as dim_cost_center,
--         toString(assumeNotNull(coalesce(raw.Department, ''))) as dim_department, ...
```

## measure_helpers.sql

Macros driven by `var('base_measures')` in `dbt_project.yml`. Each measure has keys: `name`, `expression`, `label`, `cube_type`.

### measure_select()

Generates aggregate expressions for `gold_trial_balance`.

```sql
select {{ measure_select() }}
-- Output: sum(debit_amount) as period_debit,
--         sum(credit_amount) as period_credit,
--         sum(accounting_currency_amount) as period_net_amount,
--         count(*) as transaction_count
```

### measure_passthrough(prefix='')

Generates column references for downstream models.

```sql
select {{ measure_passthrough('tb.') }}
-- Output: tb.period_debit, tb.period_credit, tb.period_net_amount, tb.transaction_count
```

## db_adapter.sql

ClickHouse-specific adapter macros. All wrap `assumeNotNull()` for null safety.

### Type Casting

| Macro | Signature | Output |
|-------|-----------|--------|
| `cast_to_string(expr)` | `(expr)` | `toString(assumeNotNull(expr))` |
| `cast_to_int64(expr)` | `(expr)` | `toInt64(assumeNotNull(expr))` |
| `cast_to_int8(expr)` | `(expr)` | `toInt8(assumeNotNull(expr))` |
| `cast_to_uint16(expr)` | `(expr)` | `toUInt16(assumeNotNull(expr))` |
| `cast_to_uint8(expr)` | `(expr)` | `toUInt8(assumeNotNull(expr))` |
| `cast_to_float64(expr)` | `(expr)` | `toFloat64(assumeNotNull(expr))` |
| `cast_to_date(expr)` | `(expr)` | `toDate(assumeNotNull(expr))` |
| `cast_to_datetime(expr)` | `(expr)` | `toDateTime(assumeNotNull(expr))` |
| `cast_to_decimal128(expr, scale)` | `(expr, scale)` | `toDecimal128(assumeNotNull(expr), scale)` |

### Date Functions

| Macro | Signature | Output |
|-------|-----------|--------|
| `extract_year(expr)` | `(expr)` | `toYear(expr)` |
| `extract_month(expr)` | `(expr)` | `toMonth(expr)` |
| `build_date_from_year_period(year_expr, period_expr)` | `(year, period)` | `toDate(concat(toString(greatest(year,1900)), '-', lpad(toString(greatest(period,1)),2,'0'), '-01'))` |

### Utility

| Macro | Signature | Output |
|-------|-----------|--------|
| `latest_value_by(val_expr, key_expr)` | `(val, key)` | `argMax(val, key)` — ClickHouse function returning val at max key |
| `string_pad_left(expr, len, ch)` | `(expr, len, ch)` | `lpad(expr, len, ch)` |
| `epm_config(order_by='tuple()')` | `(order_by)` | Returns `{'engine': 'MergeTree()', 'order_by': order_by}` for ClickHouse, `{}` otherwise |

### epm_config() Usage

```sql
{{
    config(
        materialized='table',
        **epm_config(order_by='(data_area_id, fiscal_year, fiscal_period, main_account)')
    )
}}
```

## currency_conversion.sql

### convert_currency(amount_column, from_currency_column, to_currency, rate_date_column, rate_type='Default')

Generates a correlated subquery against `silver_exchange_rates`.

```sql
select
    {{ convert_currency('local_amount', 'accounting_currency', 'USD', 'period_date') }} as translated_amount
```

Expands to:

```sql
local_amount * coalesce(
    (select er.exchange_rate
     from silver_exchange_rates as er
     where er.from_currency = accounting_currency
       and er.to_currency = 'USD'
       and er.valid_from <= period_date
       and er.valid_to >= period_date
     order by er.valid_from desc
     limit 1),
    1.0  -- Default: same-currency assumption
)
```

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `amount_column` | SQL expression | The amount to convert |
| `from_currency_column` | SQL expression | Column containing source currency code |
| `to_currency` | String literal | Target currency (e.g., `'USD'`) |
| `rate_date_column` | SQL expression | Date for rate lookup |
| `rate_type` | String | Exchange rate type (default: `'Default'`) |

## allocation_engine.sql

### allocation_engine(rule_id, driver_seed)

Single-step allocation for one rule.

```sql
{{ allocation_engine('ALLOC_001', 'allocation_drivers_headcount') }}
```

**CTE chain:**
1. `rule` — Reads rule definition from `allocation_rules` seed
2. `source_pool` — Sums `period_net_amount` from `gold_trial_balance` matching rule's source account/cost center
3. `drivers` — Computes `driver_weight = driver_value / SUM(driver_value) OVER (PARTITION BY entity, year, period)`
4. `allocated` — Cross-joins pool × rule, inner joins drivers, excludes self-allocation

**Output columns:** `allocation_rule_id`, `data_area_id`, `fiscal_year`, `fiscal_period`, `source_account`, `target_cost_center`, `target_account`, `driver_type`, `pool_amount`, `driver_weight`, `allocated_amount`

## allocation_engine_multistep.sql

### allocation_engine_multistep()

Three-step cascading allocation. No parameters — reads all rules from the `allocation_rules` seed.

```sql
{{ allocation_engine_multistep() }}
```

**Steps:**
1. **Step 1 (ALLOC_001)**: IT costs → headcount driver
2. **Step 2 (ALLOC_002)**: Facility costs + Step 1 cascade → sqm driver
3. **Step 3 (ALLOC_003)**: Management fees + Step 1+2 cascade → revenue driver

Revenue driver filters `driver_value > 0` to avoid division issues.

**Output:** `UNION ALL` of all three steps with columns: `allocation_rule_id`, `step_order`, `data_area_id`, `fiscal_year`, `fiscal_period`, `source_account`, `source_cost_center`, `target_cost_center`, `target_account`, `driver_type`, `pool_amount`, `driver_weight`, `allocated_amount`

See [Allocation Guide](../user-guide/allocation-guide.md) for a worked example.

## source_adapters/d365_account_types.sql

### map_account_type(column)

Maps D365 `MainAccountType` values to readable labels.

```sql
select {{ map_account_type('raw.Type') }} as account_type
```

| D365 Value | Output |
|-----------|--------|
| `'0'` / `'ProfitAndLoss'` | `'Profit and loss'` |
| `'1'` / `'Revenue'` | `'Revenue'` |
| `'2'` / `'Expense'` | `'Expense'` |
| `'3'` / `'BalanceSheet'` | `'Balance sheet'` |
| `'4'` / `'Asset'` | `'Asset'` |
| `'5'` / `'Liability'` | `'Liability'` |
| `'6'` / `'Equity'` | `'Equity'` |
| `'7'` / `'Total'` | `'Total'` |
| Other | Passthrough |
