{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{% set budget_dims = get_budget_dimensions() %}

with quarterly as (
    select
        stb.scenario_id,
        stb.data_area_id,
        stb.fiscal_year,
        ph.fiscal_quarter,
        stb.main_account,
        stb.account_name,
        stb.account_type_name,
        {{ dim_select(prefix='stb.', dims=budget_dims) }},
        sum(stb.amount) as quarter_amount
    from {{ ref('gold_scenario_trial_balance') }} as stb
    left join {{ ref('gold_period_hierarchy') }} as ph
        on stb.fiscal_period = ph.fiscal_period
    where stb.scenario_id in ('ACTUAL', 'BUDGET')
    group by
        stb.scenario_id,
        stb.data_area_id,
        stb.fiscal_year,
        ph.fiscal_quarter,
        stb.main_account,
        stb.account_name,
        stb.account_type_name,
        {{ dim_group_by(prefix='stb.', dims=budget_dims) }}
),

actuals_q as (
    select * from quarterly where scenario_id = 'ACTUAL'
),

budgets_q as (
    select * from quarterly where scenario_id = 'BUDGET'
)

select
    coalesce(a.data_area_id, b.data_area_id) as data_area_id,
    coalesce(a.fiscal_year, b.fiscal_year) as fiscal_year,
    coalesce(a.fiscal_quarter, b.fiscal_quarter) as fiscal_quarter,
    coalesce(a.main_account, b.main_account) as main_account,
    coalesce(a.account_name, b.account_name, '') as account_name,
    coalesce(a.account_type_name, b.account_type_name, '') as account_type_name,
    {{ dim_coalesce('a', 'b', dims=budget_dims) }},
    coalesce(a.quarter_amount, 0) as actual_amount,
    coalesce(b.quarter_amount, 0) as budget_amount,
    coalesce(a.quarter_amount, 0) - coalesce(b.quarter_amount, 0) as variance_abs,
    case
        when b.quarter_amount is not null and b.quarter_amount != 0
        then (coalesce(a.quarter_amount, 0) - b.quarter_amount) / abs(b.quarter_amount) * 100
        else null
    end as variance_pct
from actuals_q as a
full outer join budgets_q as b
    on a.data_area_id = b.data_area_id
    and a.fiscal_year = b.fiscal_year
    and a.fiscal_quarter = b.fiscal_quarter
    and a.main_account = b.main_account
    {{ dim_join_on('a', 'b', dims=budget_dims) }}
