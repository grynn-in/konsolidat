{{ config(severity='warn') }}
-- Frozen cost allocations whose origin pool no longer matches the trial balance
-- (konsol#269, T6, W6). A run frozen at approval keeps the amounts it was approved
-- at (gold_cost_allocation_frozen); if gold_scenario_trial_balance has since
-- changed, the frozen pool differs from the pool the same run would get today.
-- One row per frozen run x account x origin member. Warn, not error: a frozen run
-- is meant to differ from later data; this tells the accountant it has.
-- The current pool is the macro's own (cost_allocation_pools), so the rule is
-- not written twice. Only keys present in the frozen table are judged, since the
-- current pools also cover origins that have no coefficients (and so no lines).
-- UNION ALL + GROUP BY, not a join: join_use_nulls=0 would fill a missing side with 0.
with runs as (
    select *
    from {{ source('epm_staging', 'cost_allocation_runs') }}
    where amounts_after_approval = 'Freeze at Approval'
),

sides as (
    select run, main_account, origin_member, max(origin_amount) as pool, 'frozen' as side
    from {{ ref('gold_cost_allocation_frozen') }}
    where line_type = 'sent'
    group by run, main_account, origin_member

    union all

    select run, main_account, origin_member, origin_amount as pool, 'current' as side
    from ({{ cost_allocation_pools('runs') }})
)

select
    run,
    main_account,
    origin_member,
    sumIf(pool, side = 'frozen') as frozen_pool,
    sumIf(pool, side = 'current') as current_pool
from sides
group by run, main_account, origin_member
having countIf(side = 'frozen') > 0 and frozen_pool != current_pool
