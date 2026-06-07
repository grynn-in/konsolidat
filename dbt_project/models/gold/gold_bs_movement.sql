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
    coalesce(
        lagInFrame(cumulative_balance) over (
            partition by data_area_id, main_account, {{ dim_partition_by() }}
            order by fiscal_year, fiscal_period
            rows between unbounded preceding and unbounded following
        ),
        0
    ) as opening_balance,
    {{ measure_passthrough() }},
    period_net_amount as period_movement,
    cumulative_balance as closing_balance
from {{ ref('gold_balance_sheet') }}
