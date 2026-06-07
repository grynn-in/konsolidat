{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

select
    curr.data_area_id,
    curr.fiscal_year,
    curr.fiscal_period,
    curr.main_account,
    curr.account_name,
    curr.account_type_name,
    curr.is_balance_sheet,
    curr.is_pnl,
    {{ dim_select(prefix='curr.') }},
    curr.period_net_amount as current_amount,
    coalesce(py.period_net_amount, 0) as prior_year_amount,
    curr.period_net_amount - coalesce(py.period_net_amount, 0) as yoy_variance_abs,
    case
        when py.period_net_amount is not null and py.period_net_amount != 0
        then (curr.period_net_amount - py.period_net_amount) / abs(py.period_net_amount) * 100
        else null
    end as yoy_variance_pct
from {{ ref('gold_trial_balance') }} as curr
left join {{ ref('gold_trial_balance') }} as py
    on curr.data_area_id = py.data_area_id
    and curr.fiscal_year = py.fiscal_year + 1
    and curr.fiscal_period = py.fiscal_period
    and curr.main_account = py.main_account
    {{ dim_join_on('curr', 'py') }}
