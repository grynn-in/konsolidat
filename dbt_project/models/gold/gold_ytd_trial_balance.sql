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
{# Orchestrator run filters (opt-in; no var => no predicate => full build).
   scope_filter is safe (the YTD window partitions by data_area_id, so dropping
   other entities never changes a kept entity's cumulative total). period_filter
   uses include_period=false: the YTD running sum needs EVERY prior period within
   the year, so a single-period predicate would corrupt it — the fiscal_year
   predicate is still applied (year-bounded, and the sum partitions by year). #}
where 1 = 1
    {{ period_filter(include_period=false) }}
    {{ scope_filter() }}
