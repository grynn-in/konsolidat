{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{% set budget_dims = get_budget_dimensions() %}

with ytd_by_scenario as (
    select
        scenario_id,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        account_name,
        account_type_name,
        {{ dim_select(dims=budget_dims) }},
        sum(amount) over (
            partition by scenario_id, data_area_id, fiscal_year, main_account,
                         {{ dim_partition_by(dims=budget_dims) }}
            order by fiscal_period
            rows between unbounded preceding and current row
        ) as ytd_amount
    from {{ ref('gold_scenario_trial_balance') }}
    where scenario_id in ('ACTUAL', 'BUDGET')
),

actuals_ytd as (
    select * from ytd_by_scenario where scenario_id = 'ACTUAL'
),

budgets_ytd as (
    select * from ytd_by_scenario where scenario_id = 'BUDGET'
)

select
    coalesce(a.data_area_id, b.data_area_id) as data_area_id,
    coalesce(a.fiscal_year, b.fiscal_year) as fiscal_year,
    coalesce(a.fiscal_period, b.fiscal_period) as fiscal_period,
    coalesce(a.main_account, b.main_account) as main_account,
    coalesce(a.account_name, b.account_name, '') as account_name,
    coalesce(a.account_type_name, b.account_type_name, '') as account_type_name,
    {{ dim_coalesce('a', 'b', dims=budget_dims) }},
    coalesce(a.ytd_amount, 0) as ytd_actual,
    coalesce(b.ytd_amount, 0) as ytd_budget,
    coalesce(a.ytd_amount, 0) - coalesce(b.ytd_amount, 0) as ytd_variance_abs,
    case
        when b.ytd_amount is not null and b.ytd_amount != 0
        then (coalesce(a.ytd_amount, 0) - b.ytd_amount) / abs(b.ytd_amount) * 100
        else null
    end as ytd_variance_pct
from actuals_ytd as a
full outer join budgets_ytd as b
    on a.data_area_id = b.data_area_id
    and a.fiscal_year = b.fiscal_year
    and a.fiscal_period = b.fiscal_period
    and a.main_account = b.main_account
    {{ dim_join_on('a', 'b', dims=budget_dims) }}
