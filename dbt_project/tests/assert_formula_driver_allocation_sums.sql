-- PRD-19 Test: Allocations using composite/conditional drivers must still sum to pool
select
    ar.allocation_rule_id,
    ar.data_area_id,
    ar.fiscal_year,
    ar.fiscal_period,
    ar.pool_amount,
    sum(ar.allocated_amount) as total_allocated,
    abs(ar.pool_amount - sum(ar.allocated_amount)) as gap
from {{ ref('gold_allocation_results') }} as ar
inner join {{ source('epm_staging', 'allocation_rules') }} as sr
    on ar.allocation_rule_id = sr.allocation_rule_id
where sr.driver_formula != ''
group by ar.allocation_rule_id, ar.data_area_id, ar.fiscal_year, ar.fiscal_period, ar.pool_amount
having abs(ar.pool_amount - sum(ar.allocated_amount)) > 0.01
