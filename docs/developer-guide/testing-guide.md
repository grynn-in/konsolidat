# Testing Guide

Konsolidat has 26 data quality assertion tests covering trial balance integrity, consolidation math, allocation completeness, budget spreading, and variance logic.

## Test Philosophy

Each test is a SQL query that returns rows violating an assertion. **Zero rows = pass.** Tests are named `assert_{what_is_being_tested}` and live in `dbt_project/tests/`.

Tests have two severity levels:
- **`error`** (default): Fails the build. Used for critical invariants.
- **`warn`**: Logs a warning but doesn't fail. Used for data quality checks that may have known exceptions.

```sql
{{ config(severity='warn') }}
```

## Test Catalog

### Trial Balance & GL Integrity

| Test | Severity | Assertion |
|------|----------|-----------|
| `assert_trial_balance_balances` | warn | `\|SUM(period_debit) − SUM(period_credit)\| ≤ 0.01` per entity/year/period |
| `assert_silver_gl_debit_credit_balance` | warn | `\|SUM(debit) − SUM(credit)\| ≤ 0.01` at GL level per entity/year |
| `assert_gl_accounts_in_chart` | error | All GL account codes exist in the chart of accounts |
| `assert_exchange_rate_positive` | error | All exchange rates are > 0 |

### P&L and Balance Sheet

| Test | Severity | Assertion |
|------|----------|-----------|
| `assert_pnl_only_pnl_accounts` | error | P&L model contains only Revenue and Expense account types |
| `assert_bs_only_bs_accounts` | error | BS model contains only Asset, Liability, and Equity account types |

### Consolidation

| Test | Severity | Assertion |
|------|----------|-----------|
| `assert_translated_amount_formula` | error | `\|translated − (local × rate)\| ≤ 0.01` |
| `assert_group_amount_formula` | error | `\|group − (translated × ownership)\| ≤ 0.01` |
| `assert_nci_plus_group_equals_translated` | error | `\|translated − (group + nci)\| ≤ 0.01` |
| `assert_nci_zero_for_full_ownership` | error | NCI = 0 when ownership = 100% |
| `assert_bs_uses_closing_rate` | error | BS accounts use the closing exchange rate |
| `assert_pnl_uses_average_rate` | error | P&L accounts use the average exchange rate |
| `assert_cta_not_zero_when_rates_differ` | error | CTA is non-zero when closing ≠ average rate |
| `assert_cta_zero_for_same_currency` | error | CTA = 0 when entity currency = reporting currency |
| `assert_ic_elimination_nets_zero` | error | IC eliminations net to zero per group/period |
| `assert_topside_journal_balanced` | error | Each top-side journal balances (debits = credits) |
| `assert_adjustment_type_populated` | error | `adjustment_type` is never null in FCTB |
| `assert_fctb_entity_layer_ties` | error | Entity layer in FCTB ties to consolidated TB group_amount |

### Allocation

| Test | Severity | Assertion |
|------|----------|-----------|
| `assert_each_step_sums_to_pool` | error | `\|pool_amount − SUM(allocated)\| ≤ 0.01` per step |
| `assert_no_self_allocation` | error | Source cost center never appears as target |

### Budget & Variance

| Test | Severity | Assertion |
|------|----------|-----------|
| `assert_spread_sums_to_annual` | error | `\|annual − SUM(period_amount)\| ≤ 0.01` |
| `assert_spread_has_12_periods` | error | Each budget line produces exactly 12 periods |
| `assert_variance_abs_formula` | error | `\|variance_abs − (actual − budget)\| ≤ 0.01` |
| `assert_favorable_revenue` | error | Revenue: favorable=1 when actual > budget |
| `assert_favorable_expense` | error | Expense: favorable=1 when actual < budget |

### YTD

| Test | Severity | Assertion |
|------|----------|-----------|
| `assert_ytd_p12_equals_annual` | warn | YTD at period 12 = sum of all 12 periods |

## Running Tests

```bash
# Run all tests
dbt test

# Run tests for a specific model
dbt test --select gold_trial_balance

# Run a single test
dbt test --select assert_spread_sums_to_annual

# Run tests by tag
dbt test --select tag:gold

# Run only warn-severity tests
dbt test --severity warn
```

## Writing a New Test

### 1. Create the Test File

Create `dbt_project/tests/assert_your_condition.sql`:

```sql
-- Description of what this test checks
-- Reference: PRD-X or business rule

select
    key_column_1,
    key_column_2,
    computed_value,
    expected_value,
    abs(computed_value - expected_value) as gap
from {{ ref('gold_your_model') }}
where abs(computed_value - expected_value) > 0.01
```

### 2. Guidelines

- **Return failing rows**: The query selects rows that violate the rule
- **Include context**: Return enough columns to diagnose the issue (entity, year, period, the values compared)
- **Use 0.01 tolerance**: For financial amounts, floating-point comparison needs a tolerance
- **Reference PRDs**: Comment which product requirement the test validates
- **Add severity**: Use `{{ config(severity='warn') }}` for non-critical checks

### 3. Test Patterns

**Balance check** (debits = credits):
```sql
select data_area_id, fiscal_year, fiscal_period,
       abs(sum(period_debit) - sum(period_credit)) as imbalance
from {{ ref('gold_trial_balance') }}
group by data_area_id, fiscal_year, fiscal_period
having abs(sum(period_debit) - sum(period_credit)) > 0.01
```

**Formula validation** (computed vs expected):
```sql
select *,
       abs(translated_amount - (local_amount * translation_rate)) as gap
from {{ ref('gold_consolidated_trial_balance') }}
where abs(translated_amount - (local_amount * translation_rate)) > 0.01
```

**Referential integrity** (FK exists in parent):
```sql
select gl.main_account
from {{ ref('silver_gl_entries') }} as gl
left join {{ ref('silver_main_accounts') }} as ma
    on gl.main_account = ma.main_account_id
where ma.main_account_id is null
```

**Count validation** (expected number of rows):
```sql
select scenario_id, data_area_id, fiscal_year, main_account,
       count(distinct fiscal_period) as period_count
from {{ ref('gold_spread_budget') }}
group by scenario_id, data_area_id, fiscal_year, main_account
having count(distinct fiscal_period) != 12
```

### 4. Using Dimension Macros in Tests

When your test involves dimension columns, use the macros:

```sql
select
    data_area_id, fiscal_year, main_account,
    {{ dim_select() }},
    ytd_net_amount,
    annual_total,
    abs(ytd_net_amount - annual_total) as gap
from (
    select *, sum(period_net_amount) over (
        partition by data_area_id, fiscal_year, main_account
        {{ dim_partition_by() }}
    ) as annual_total
    from {{ ref('gold_ytd_trial_balance') }}
    where fiscal_period = 12
)
where abs(ytd_net_amount - annual_total) > 0.01
```

## YAML Schema Tests

In addition to custom SQL tests, column-level tests are defined in `_*__models.yml` files:

```yaml
columns:
  - name: data_area_id
    tests:
      - not_null
  - name: main_account_id
    tests:
      - not_null
      - unique
```

Available schema tests: `not_null`, `unique`, `accepted_values`, `relationships`.

## Next Steps

- [Extending dbt Models](extending-dbt-models.md) — Adding the model to test
- [Operations Runbook](../admin-guide/operations-runbook.md) — Running tests in production
- [Data Dictionary](../data-dictionary/gold-models.md) — What's being tested
