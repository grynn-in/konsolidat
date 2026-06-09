-- PRD-18 Test: Reciprocal allocations must converge (delta shrinks each iteration)
-- Check that the last iteration's allocated amounts are < 0.01 of the first
select
    'not_converged' as error
from (
    select
        allocation_rule_id,
        data_area_id,
        sum(case when final_iteration >= 9 then abs(allocated_amount) else 0 end) as late_amount,
        sum(abs(allocated_amount)) as total_amount
    from {{ ref('gold_allocation_results') }}
    where driver_type in (
        select driver_type from {{ source('epm_staging', 'allocation_rules') }}
        where allocation_method = 'reciprocal'
    )
    group by allocation_rule_id, data_area_id
) as conv
where total_amount > 0
  and late_amount / total_amount > 0.01
