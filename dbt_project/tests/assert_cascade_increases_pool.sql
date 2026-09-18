-- PRD-17 Test: When step N cascades into step N+1's source cost center,
-- step N+1's pool must be >= its TB base amount (cascade adds to pool)
-- This is a structural test: steps 2+ should have pool >= base when cascade exists
--
-- konsolidat#220: this test groups the trial balance by the site's cost-centre
-- dimension. A site that declares none has no such column, and the allocation
-- engine produces no rows there, so the test has nothing to check and asserts
-- nothing rather than failing on a missing column. That a site has allocation
-- RULES without declaring the dimension is a misconfiguration, and it is caught
-- loudly by assert_allocation_role_declared.sql, not swallowed here.
--
-- depends_on: {{ ref('gold_allocation_results') }}
-- depends_on: {{ ref('gold_trial_balance') }}
{% if get_allocation_cost_center_dim() == '' %}
select
    '' as allocation_rule_id,
    '' as data_area_id,
    0 as fiscal_year,
    0 as fiscal_period,
    0 as pool_amount,
    0 as base_amount
where 1 = 0
{% else %}
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
{% endif %}
