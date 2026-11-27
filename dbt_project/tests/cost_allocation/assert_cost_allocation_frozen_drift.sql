-- Frozen cost allocations whose origin pool no longer matches the trial balance
-- (konsol#269, T6, W6). A run frozen at approval keeps the amounts it was approved
-- at (gold_cost_allocation_frozen); if gold_scenario_trial_balance has since
-- changed, the frozen pool differs from the pool the same run would get today.
-- One row per frozen run x account x origin member. Warn, not error: a frozen run
-- is meant to differ from later data; this tells the accountant it has.
-- The current pool is the macro's own (cost_allocation_pools), so the rule is
-- not written twice. Pools are read from the origin's own sent lines
-- (hop_kind = 'own'): a declared-mode pass-through sent line sits on the allocation account.
-- Declared Rate origins (2b-2 W4d) are left out on both sides: a rate origin's
-- frozen origin_amount is its RATE, not a pool, and its trial balance pool never
-- enters its lines (it feeds the absorption variance instead), so comparing the
-- two would report every rate origin; assert_cost_allocation_absorption_frozen_drift
-- (W7) judges that pool on the frozen absorption rows. The frozen side drops lines with basis =
-- 'Declared Rate'; the current side drops the run's rate senders
-- (cost_allocation_rate_origins, the rule the lines use).
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

rate_origins as (
    {{ cost_allocation_rate_origins('runs') }}
),

sides as (
    select run, main_account, origin_member, max(origin_amount) as pool, 'frozen' as side
    from {{ ref('gold_cost_allocation_frozen') }}
    where line_type = 'sent' and hop_kind = 'own' and basis != 'Declared Rate'
    group by run, main_account, origin_member

    union all

    select run, main_account, origin_member, origin_amount as pool, 'current' as side
    from ({{ cost_allocation_pools('runs') }})
    where (run, origin_member) in (
        select run, origin_member from {{ source('epm_staging', 'cost_allocation_coefficients') }}
    )
    and (run, origin_member) not in (select run, origin_member from rate_origins)
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
