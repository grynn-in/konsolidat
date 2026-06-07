{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    account_name,
    {{ dim_select() }},
    reporting_currency,
    adjustment_type,
    journal_id,
    amount,
    sum(amount) over (
        partition by consolidation_group, data_area_id, fiscal_year, main_account,
                     adjustment_type, {{ dim_partition_by() }}
        order by fiscal_period
        rows between unbounded preceding and current row
    ) as ytd_amount
from {{ ref('gold_fully_consolidated_tb') }}
