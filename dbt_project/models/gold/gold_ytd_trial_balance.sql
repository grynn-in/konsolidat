{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

select
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    account_name,
    account_type_name,
    is_balance_sheet,
    is_pnl,
    {{ dim_select() }},
    {{ measure_passthrough() }},
    sum(period_net_amount) over (
        partition by data_area_id, fiscal_year, main_account, {{ dim_partition_by() }}
        order by fiscal_period
        rows between unbounded preceding and current row
    ) as ytd_net_amount
from {{ ref('gold_trial_balance') }}
