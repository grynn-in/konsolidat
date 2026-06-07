{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

select
    tb.data_area_id,
    tb.fiscal_year,
    ph.fiscal_quarter,
    tb.main_account,
    tb.account_name,
    tb.account_type_name,
    {{ dim_select(prefix='tb.') }},
    sum(tb.period_net_amount) as quarter_net_amount,
    sum(tb.period_debit) as quarter_debit,
    sum(tb.period_credit) as quarter_credit
from {{ ref('gold_trial_balance') }} as tb
left join {{ ref('gold_period_hierarchy') }} as ph
    on tb.fiscal_period = ph.fiscal_period
where tb.is_pnl = 1
group by
    tb.data_area_id,
    tb.fiscal_year,
    ph.fiscal_quarter,
    tb.main_account,
    tb.account_name,
    tb.account_type_name,
    {{ dim_group_by(prefix='tb.') }}
