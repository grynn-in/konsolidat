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
    {{ measure_passthrough() }}
from {{ ref('gold_trial_balance') }}
where is_pnl = 1
