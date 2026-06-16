{{
    config(
        engine=cluster_engine('MergeTree()'),
        order_by='tuple()',
        cluster=cluster_name()
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
    {{ measure_select() }}
from {{ ref('silver_gl_entries') }}
group by
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    account_name,
    account_type_name,
    is_balance_sheet,
    is_pnl,
    {{ dim_group_by() }}
