-- PRD-20 Test: Sum of all tier allocations per rule must not exceed the pool
select
    allocation_rule_id,
    data_area_id,
    fiscal_year,
    fiscal_period,
    max(pool_amount) as pool_amount,
    sum(allocated_amount) as total_tiered
from {{ ref('gold_allocation_results') }}
where driver_type = 'tiered'
group by allocation_rule_id, data_area_id, fiscal_year, fiscal_period
having sum(allocated_amount) > max(pool_amount) + 0.01
