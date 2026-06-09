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
