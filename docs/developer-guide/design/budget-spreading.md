# Budget Spreading / Seasonality Profiles

## Problem
Budget input is per-period line items. In practice, planners often enter annual amounts and expect the system to spread them across months using a profile:
- **Even** — divide by 12
- **Seasonal** — use historical seasonal pattern
- **Custom** — user-defined weights per period

Currently there is no spreading logic — users must enter all 12 periods manually.

## Requirements

### R1: Spread profile seed
New seed `spread_profiles.csv`:
```csv
profile_id,profile_name,fiscal_period,weight
EVEN,Even Spread,1,1.0
EVEN,Even Spread,2,1.0
...
EVEN,Even Spread,12,1.0
SEASONAL_RETAIL,Retail Seasonal,1,0.6
SEASONAL_RETAIL,Retail Seasonal,2,0.5
...
SEASONAL_RETAIL,Retail Seasonal,11,1.8
SEASONAL_RETAIL,Retail Seasonal,12,2.5
```
Weights are relative — the model normalizes them to sum to 1.0.

### R2: API endpoint for annual budget input
- `POST /api/v1/budget-annual` — accepts:
  ```json
  {
    "scenario_id": "BUDGET_2025",
    "legal_entity_id": "USMF",
    "fiscal_year": 2025,
    "main_account": "6100",
    "annual_amount": 1200000,
    "spread_profile_id": "EVEN",
    "submitted_by": "user@co.com"
  }
  ```
- API spreads the annual amount into 12 period rows in `budget_input` staging table

### R3: dbt model `gold_spread_budget`
- Reads annual budget entries (where `fiscal_period = 0` convention) from staging
- Joins with `spread_profiles` seed
- Normalizes weights: `period_weight = weight / sum(weight) over profile`
- Calculates: `period_amount = annual_amount × period_weight`
- Outputs 12 rows per annual input

### R4: Integration with scenario TB
- `gold_scenario_trial_balance` must include spread budget entries
- Either via the staging table (API does the spreading) or via the dbt model (dbt does the spreading)
- **Decision**: API does the spreading into staging → simpler, dbt just reads staging as-is

## Acceptance Tests

| Test | Assertion |
|------|-----------|
| `assert_even_spread_equal_periods` | EVEN profile: all 12 periods have same amount (annual / 12) within 0.01 |
| `assert_spread_sums_to_annual` | Per annual input: sum of 12 period amounts = annual_amount within 0.01 |
| `assert_seasonal_weights_applied` | Period amounts are proportional to profile weights |
| `assert_spread_profile_weights_positive` | All weights > 0 |

## Out of Scope
- Driver-based planning (revenue × price × volume)
- Rolling forecast auto-spread
- Phasing templates at account-group level
