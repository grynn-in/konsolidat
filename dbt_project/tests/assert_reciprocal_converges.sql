-- PRD-18 Test: Reciprocal allocations must converge (delta shrinks each iteration)
-- Check that the last iteration's allocated amounts are < 0.01 of the first
--
-- DISABLED: this assertion can't be evaluated today. It reads gold_allocation_results,
-- which is materialized only by allocation_engine_multistep() (step_down rules) and
-- carries no reciprocal-solver output — there is no iteration counter column, and
-- allocation_engine_reciprocal() (which emits `final_iteration`) is wired into no model.
-- The convergence check needs that engine's `final_iteration` (NOT step_order, which is
-- the multistep cascade order — a different concept). Re-enable once reciprocal results
-- are materialized. Left enabled=false rather than rewritten to always-pass. See #70.
{{ config(enabled=false) }}
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
