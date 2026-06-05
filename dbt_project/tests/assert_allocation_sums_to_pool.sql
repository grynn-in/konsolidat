-- Test: Allocated amounts must sum to pool amount (zero-sum allocation)
-- Excludes the source cost center which is not in the allocation
select
    allocation_rule_id,
    data_area_id,
    fiscal_year,
    fiscal_period,
    pool_amount,
    sum(allocated_amount) as total_allocated,
    abs(pool_amount - sum(allocated_amount)) as allocation_gap
from {{ ref('gold_allocation_results') }}
group by allocation_rule_id, data_area_id, fiscal_year, fiscal_period, pool_amount
having abs(pool_amount - sum(allocated_amount)) > 0.01
