# PRD-3: Multi-Step Cascading Allocations

## Problem
Current allocation engine runs a single pass per rule. Real allocations require ordered steps where output of step N becomes input to step N+1. Example:
1. Step 1: Allocate IT costs to all departments by headcount
2. Step 2: Allocate Facilities costs (which now include some IT) by square meters
3. Step 3: Allocate shared services to business units by revenue

## Requirements

### R1: Step ordering in allocation_rules seed
Add column `step_order` (integer) to `allocation_rules.csv`:
```
allocation_rule_id,rule_name,step_order,source_account,source_cost_center,driver_type,target_account,description
ALLOC_001,IT Cost Allocation,1,7100,IT,headcount,7100,Step 1: IT by headcount
ALLOC_002,Facility Allocation,2,7200,FACILITY,sqm,7200,Step 2: Facilities by sqm
ALLOC_003,Mgmt Fee Allocation,3,7300,MGMT,revenue,7300,Step 3: Mgmt by revenue
```

### R2: Cascading allocation macro
New macro `allocation_engine_multistep` that:
1. Reads all rules ordered by `step_order`
2. For step 1: source pool comes from `gold_trial_balance` (as today)
3. For step N>1: source pool comes from `gold_trial_balance` PLUS allocated amounts from steps 1..N-1
4. Each step produces allocation rows with `step_order` column

### R3: New model `gold_allocation_results_v2`
- Replaces `gold_allocation_results`
- Contains all steps' results
- Columns: step_order, allocation_rule_id, data_area_id, fiscal_year, fiscal_period, source_account, target_cost_center, driver_type, pool_amount, driver_weight, allocated_amount

### R4: Driver seed flexibility
- Each rule references its own driver seed via `driver_seed_name` column
- `allocation_drivers_headcount` (existing), add `allocation_drivers_sqm`, `allocation_drivers_revenue`

## Acceptance Tests

| Test | Assertion |
|------|-----------|
| `assert_allocation_step_order` | All rows have valid step_order matching their rule |
| `assert_step2_pool_includes_step1` | Step 2 pool_amount > original TB amount for that account (proves cascade) |
| `assert_each_step_sums_to_pool` | Per step: sum(allocated_amount) = pool_amount within 0.01 |
| `assert_no_self_allocation` | No row has target_cost_center = source_cost_center |

## Out of Scope
- Circular (iterative) allocations
- Reciprocal allocation method
