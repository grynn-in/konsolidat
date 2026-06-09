-- PRD-17 Test: When step N cascades into step N+1's source cost center,
-- step N+1's pool must be >= its TB base amount (cascade adds to pool)
-- This is a structural test: steps 2+ should have pool >= base when cascade exists
select
    ar.allocation_rule_id,
    ar.data_area_id,
    ar.fiscal_year,
    ar.fiscal_period,
    ar.pool_amount,
    tb_sum.base_amount
from {{ ref('gold_allocation_results') }} as ar
inner join (
    select
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        {{ get_allocation_cost_center_dim() }},
        sum(period_net_amount) as base_amount
    from {{ ref('gold_trial_balance') }}
    group by data_area_id, fiscal_year, fiscal_period, main_account, {{ get_allocation_cost_center_dim() }}
) as tb_sum
    on ar.data_area_id = tb_sum.data_area_id
    and ar.fiscal_year = tb_sum.fiscal_year
    and ar.fiscal_period = tb_sum.fiscal_period
    and ar.source_account = tb_sum.main_account
    and ar.source_cost_center = tb_sum.{{ get_allocation_cost_center_dim() }}
where ar.step_order > 1
  and ar.pool_amount < tb_sum.base_amount - 0.01
group by ar.allocation_rule_id, ar.data_area_id, ar.fiscal_year, ar.fiscal_period,
         ar.pool_amount, tb_sum.base_amount
