-- PRD-20 Test: Sum of all tier allocations per rule must not exceed the pool
-- ClickHouse rejects a HAVING that compares two different aggregates
-- (sum(...) > max(...)) — it reads one as nested inside the other. Aggregate
-- in a subquery, then compare the plain columns in the outer WHERE.
select *
from (
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
) as tiers
where total_tiered > pool_amount + 0.01
