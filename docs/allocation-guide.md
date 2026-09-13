# Allocation Guide

## How Allocations Work

Konsolidat uses a driver-based allocation engine. The process:

1. **Define a rule** as an **Allocation Rule** in konsol — specifies source account/cost center, driver type, and target account
2. **Provide driver data** as **Allocation Driver** records in konsol — values per cost center/period
3. **dbt calculates** — reads pool amount from trial balance, computes weights, distributes proportionally

The current, fuller guide is the [Allocation Guide](user-guide/allocation-guide.md).

## Allocation Rules

Use the **Allocation Rule** doctype in konsol (there are no dbt seeds; it writes through to `epm_staging.allocation_rules`).

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

Enter **Allocation Driver** records with driver values per cost center and period (written through to `epm_staging.allocation_drivers`):

| driver_type | data_area_id | cost_center | driver_value | fiscal_year | fiscal_period |
|---|---|---|---|---|---|
| headcount | USMF | SALES | 45 | 2024 | 1 |
| headcount | USMF | MARKETING | 20 | 2024 | 1 |
| headcount | USMF | OPERATIONS | 85 | 2024 | 1 |

The engine normalizes driver values to weights (each / sum = weight).

## Adding a New Allocation

1. Create an **Allocation Rule** in konsol with the next `step_order`
2. Enter **Allocation Driver** values for its driver type
3. Run `dbt build` (the multi-step engine reads the number of steps from the rules; no SQL change is needed)

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
