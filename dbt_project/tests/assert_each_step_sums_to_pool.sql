-- PRD-3 Test: Each allocation rule's allocated amounts must sum to pool amount
select
    allocation_rule_id,
    data_area_id,
    fiscal_year,
    fiscal_period,
    pool_amount,
    sum(allocated_amount) as total_allocated,
    abs(pool_amount - sum(allocated_amount)) as gap
from {{ ref('gold_allocation_results') }}
group by allocation_rule_id, data_area_id, fiscal_year, fiscal_period, pool_amount
having abs(pool_amount - sum(allocated_amount)) > 0.01
