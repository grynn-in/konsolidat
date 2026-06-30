{{
    config(
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key=['data_area_id', 'fiscal_year', 'fiscal_period'],
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# A2 / grynn-in/konsolidat#116: incremental-by-period materialization. A scoped
   close narrows the SELECT to its slice; the YTD running sum partitions by
   (data_area_id, fiscal_year), so a per-entity/year slice is self-contained.
   delete+insert keyed on (data_area_id, fiscal_year, fiscal_period) replaces only
   the in-scope keys and leaves every other entity/period intact, instead of
   OVERWRITING the table. period_filter(include_period=false) keeps every period
   of the closed year so the cumulative window stays correct within the slice.
   No vars => every key present => identical to a full table build (opt-in). #}

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
    ) as ytd_net_amount,
    {# A3: stamp this run's scope so the confinement test can isolate the rows THIS
       close actually wrote from A2-preserved siblings (empty => full build). #}
    {{ close_scope_marker() }} as _close_scope
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
