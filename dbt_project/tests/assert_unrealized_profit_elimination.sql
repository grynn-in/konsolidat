-- PRD-15 Test: Unrealized profit elimination = ending_inventory × margin_pct
select
    ie.rule_id,
    ie.consolidation_group,
    ie.fiscal_year,
    ie.fiscal_period,
    ie.elimination_amount,
    icb.ending_inventory_from_ic * (icr.margin_pct / 100.0) as expected
from {{ ref('gold_ic_eliminations') }} as ie
inner join {{ source('epm_staging', 'ic_elimination_rules') }} as icr
    on ie.rule_id = icr.rule_id
inner join {{ source('epm_staging', 'ic_balances') }} as icb
    on ie.fiscal_year = icb.fiscal_year
    and ie.fiscal_period = icb.fiscal_period
where ie.rule_type = 'unrealized_profit'
  and abs(ie.elimination_amount - icb.ending_inventory_from_ic * (icr.margin_pct / 100.0)) > 0.01
