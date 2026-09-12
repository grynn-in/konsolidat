{{
    config(
        materialized='incremental',
        incremental_strategy='append',
        pre_hook="{% if is_incremental() %}DELETE FROM {{ this }} WHERE 1 = 1 {{ period_filter(include_period=false) }} {{ scope_filter() }}{% endif %}",
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# A2 / grynn-in/konsolidat#116: incremental-by-period materialization. A scoped
   close narrows the SELECT to its slice; the YTD running sum partitions by
   (data_area_id, fiscal_year), so a per-entity/year slice is self-contained.
   The pre_hook deletes the slice with the same predicate the SELECT uses (#154:
   not just the keys the batch produced), and leaves every other entity/year
   intact. period_filter(include_period=false) keeps every period of the closed
   year so the cumulative window stays correct within the slice. No vars => the
   whole table is replaced. #}

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
