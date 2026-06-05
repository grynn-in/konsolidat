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
    {{ dim_select() }},
    {{ measure_passthrough() }},
    -- Cumulative balance for BS accounts (running sum within year)
    sum(period_net_amount) over (
        partition by data_area_id, main_account, {{ dim_partition_by() }}
        order by fiscal_year, fiscal_period
    ) as cumulative_balance
from {{ ref('gold_trial_balance') }}
where is_balance_sheet = 1
