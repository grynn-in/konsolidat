# Variance Analysis Model

## Problem
`gold_scenario_trial_balance` unions actual + budget but provides no computed variance. Users must calculate variance in Excel. A proper EPM tool provides:
- Absolute variance (actual - budget)
- Percentage variance
- Favorable/unfavorable classification (expense under-budget = favorable)

## Requirements

### R1: New model `gold_variance_analysis`
Pivots scenario data into a columnar format per account/period:

| Column | Description |
|--------|-------------|
| data_area_id | Legal entity |
| fiscal_year, fiscal_period | Period |
| main_account, account_name | Account |
| dim_cost_center, dim_department | Dimensions |
| actual_amount | From scenario_id = 'ACTUAL' |
| budget_amount | From scenario_id = 'BUDGET' |
| forecast_amount | From latest forecast scenario |
| variance_abs | actual_amount - budget_amount |
| variance_pct | variance_abs / nullif(budget_amount, 0) × 100 |
| variance_favorable | Boolean: true if variance is favorable |

### R2: Favorable/unfavorable logic
- **Revenue accounts** (account_type in revenue categories): actual > budget = favorable
- **Expense accounts** (account_type in expense categories): actual < budget = favorable
- **Asset/Liability**: not applicable (null)
- Uses `is_pnl` flag + account_type_name to determine direction

### R3: Cube schema
New Cube model `variance_analysis` with:
- Dimensions: entity, year, period, account, cost_center, department
- Measures: actual_amount, budget_amount, forecast_amount, variance_abs, variance_pct

### R4: Multi-scenario comparison
- Support comparing any two scenarios (not just actual vs budget)
- Parameterized via Cube filters: `base_scenario` and `compare_scenario`
- Default: base = ACTUAL, compare = BUDGET

## Acceptance Tests

| Test | Assertion |
|------|-----------|
| `assert_variance_abs_formula` | variance_abs = actual_amount - budget_amount within 0.01 |
| `assert_variance_pct_formula` | variance_pct = variance_abs / budget_amount × 100 (where budget ≠ 0) |
| `assert_favorable_revenue` | Revenue accounts: actual > budget → variance_favorable = true |
| `assert_favorable_expense` | Expense accounts: actual < budget → variance_favorable = true |
| `assert_no_orphan_actuals` | Every account with actuals has a budget row (or null budget) |

## Out of Scope
- Waterfall / bridge analysis (e.g., price/volume/mix decomposition)
- Trend analysis (period-over-period)
- Commentary / annotation on variances
