# Allocation Guide

## How Allocations Work

Konsolidat uses a driver-based allocation engine. The process:

1. **Define a rule** in `allocation_rules.csv` — specifies source account/cost center, driver type, and target account
2. **Provide driver data** in CSV seeds (e.g., `allocation_drivers_headcount.csv`) — values per cost center/period
3. **dbt calculates** — reads pool amount from trial balance, computes weights, distributes proportionally

## Allocation Rules

Edit `dbt_project/seeds/allocation_rules.csv` or use the Allocation Rule doctype in Frappe Desk.

| Field | Description | Example |
|-------|-------------|---------|
| `allocation_rule_id` | Unique rule ID | `ALLOC_001` |
| `rule_name` | Descriptive name | `IT Cost Allocation` |
| `source_account` | GL account to allocate from | `7100` |
| `source_cost_center` | Cost center holding the pool | `IT` |
| `driver_type` | Type of allocation driver | `headcount` |
| `target_account` | GL account to allocate to | `7100` |
| `description` | Free-text description | `Allocate IT costs by headcount` |

## Driver Data

Create CSV seeds with driver values per cost center and period:

```csv
data_area_id,cost_center,driver_value,fiscal_year,fiscal_period
USMF,SALES,45,2024,1
USMF,MARKETING,20,2024,1
USMF,OPERATIONS,85,2024,1
```

The engine normalizes driver values to weights (each / sum = weight).

## Adding a New Allocation

1. Add a row to `allocation_rules.csv`
2. Create a new driver CSV (e.g., `allocation_drivers_sqm.csv`)
3. Update `gold_allocation_results.sql` to add a `UNION ALL` with the new rule
4. Run `dbt seed && dbt build --select gold_allocation_results`

## Validation

The test `assert_allocation_sums_to_pool.sql` verifies that allocated amounts sum exactly to the source pool. If this test fails, check:
- Driver weights sum to 1.0
- Source pool has data for the specified account/cost center
- No rounding issues in decimal precision

## Example

**Rule**: Allocate IT costs (account 7100, cost center IT) by headcount

| Cost Center | Headcount | Weight | Pool = $175K | Allocated |
|-------------|-----------|--------|-------------|-----------|
| SALES | 45 | 0.257 | | $44,975 |
| MARKETING | 20 | 0.114 | | $19,950 |
| OPERATIONS | 85 | 0.486 | | $85,050 |
| FINANCE | 15 | 0.086 | | $15,050 |
| HR | 10 | 0.057 | | $9,975 |
| **Total** | **175** | **1.000** | **$175,000** | **$175,000** |
