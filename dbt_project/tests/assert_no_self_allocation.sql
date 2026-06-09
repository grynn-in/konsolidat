-- PRD-3 Test: No allocation should target the source cost center
select
    allocation_rule_id,
    data_area_id,
    fiscal_year,
    fiscal_period,
    source_account,
    target_cost_center
from {{ ref('gold_allocation_results') }} as ar
inner join {{ ref('allocation_rules') }} as r
    on ar.allocation_rule_id = r.allocation_rule_id
where ar.target_cost_center = r.source_cost_center
