-- Frozen cost allocations whose origin pool no longer matches the trial balance
-- (konsol#269, T6, W6). A run frozen at approval keeps the amounts it was approved
-- at (gold_cost_allocation_frozen); if gold_scenario_trial_balance has since
-- changed, the frozen pool differs from the pool the same run would get today.
-- One row per frozen run x account x origin member. Warn, not error: a frozen run
-- is meant to differ from later data; this tells the accountant it has.
-- The current pool is the macro's own (cost_allocation_pools), so the rule is
-- not written twice. Pools are read from the origin's own sent lines (sender =
-- origin): a declared-mode pass-through sent line sits on the allocation account.
-- Both directions are judged: a frozen key whose origin has
-- lost its TB data, and an origin that got TB data after the freeze (no frozen
-- lines, current pool != 0). The current side is limited to origins that have
-- coefficients for the run, since an origin without them never gets lines.
-- UNION ALL + GROUP BY, not a join: join_use_nulls=0 would fill a missing side with 0.
{{ config(severity='warn') }}
with runs as (
    select *
    from {{ source('epm_staging', 'cost_allocation_runs') }}
    where amounts_after_approval = 'Freeze at Approval'
),

sides as (
    select run, main_account, origin_member, max(origin_amount) as pool, 'frozen' as side
    from {{ ref('gold_cost_allocation_frozen') }}
    where line_type = 'sent' and sender_member = origin_member
    group by run, main_account, origin_member

    union all

    select run, main_account, origin_member, origin_amount as pool, 'current' as side
    from ({{ cost_allocation_pools('runs') }})
    where (run, origin_member) in (
        select run, origin_member from {{ source('epm_staging', 'cost_allocation_coefficients') }}
    )
)

select
    run,
    main_account,
    origin_member,
    sumIf(pool, side = 'frozen') as frozen_pool,
    sumIf(pool, side = 'current') as current_pool
from sides
group by run, main_account, origin_member
having frozen_pool != current_pool
