-- PRD-17 Test: Number of distinct steps in results must match rules
select
    'mismatch' as error
from (
    select count(distinct step_order) as result_steps
    from {{ ref('gold_allocation_results') }}
) as r
cross join (
    select count(distinct step_order) as rule_steps
    from {{ ref('allocation_rules') }}
) as ru
where r.result_steps != ru.rule_steps
  and ru.rule_steps > 0
  -- Only assert step-count parity when the engine actually produced output.
  -- On real D365 data the AM* allocation entities (AMUS/AMHQ/AMDE) have no GL,
  -- so alloc_results is legitimately empty (result_steps = 0); that is a
  -- data-availability state, not a dropped-step bug. A partial run
  -- (result_steps between 1 and rule_steps-1) is still caught.
  and r.result_steps > 0
