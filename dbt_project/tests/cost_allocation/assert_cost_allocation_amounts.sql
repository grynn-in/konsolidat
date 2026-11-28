-- The amounts of a published cost allocation follow the run's policy
-- (konsol#269, W5b). A 'Follow Latest Data' run is live: frozen_at is NULL and
-- its origin pool equals the current trial balance pool. A 'Freeze at Approval'
-- run carries frozen_at on every line; its amount is judged against the trial
-- balance by assert_cost_allocation_frozen_drift (warn), not here, because a
-- frozen run is meant to differ from later data.
-- The stamp check can fire on a real build only if a model's stamp expression
-- changes. The `stale` check compares the model with the macro's pools, so within
-- one full build it cannot fire; it fires when gold_scenario_trial_balance is
-- rebuilt without rebuilding this model (a partial build) or on a seeded table.
-- Pools come from the origin's own sent lines (hop_kind = 'own'), not the declared-mode
-- pass-through lines on the allocation account. A Declared Rate origin (2b-2 W4d)
-- is stamped like any other but not judged for staleness: its origin_amount is its
-- RATE, and its trial balance pool never enters its lines; both sides of `stale`
-- leave it out (basis on the lines, cost_allocation_rate_origins on the current side).
-- Rows returned are violations. UNION ALL + GROUP BY, not a join: join_use_nulls=0.
with runs as (
    select * from {{ source('epm_staging', 'cost_allocation_runs') }}
),

live_runs as (
    select * from runs where amounts_after_approval = 'Follow Latest Data'
),

rate_origins as (
    {{ cost_allocation_rate_origins('live_runs') }}
),

published as (
    select
        a.run as run, a.main_account as main_account, a.origin_member as origin_member, a.basis as basis,
        max(a.origin_amount) as pool, max(r.amounts_after_approval) as policy,
        countIf(a.frozen_at is null) as unstamped, countIf(a.frozen_at is not null) as stamped
    from {{ ref('gold_cost_allocation') }} a
    inner join runs r on r.name = a.run
    where a.line_type = 'sent' and a.hop_kind = 'own'
    group by a.run, a.main_account, a.origin_member, a.basis
),

stamp_violations as (
    select run, main_account, origin_member, 'frozen_at does not match the run policy' as problem
    from published
    where (policy = 'Follow Latest Data' and stamped > 0)
       or (policy = 'Freeze at Approval' and unstamped > 0)
),

sides as (
    select run, main_account, origin_member, pool, 'published' as side
    from published
    where policy = 'Follow Latest Data' and basis != 'Declared Rate'

    union all

    select run, main_account, origin_member, origin_amount as pool, 'current' as side
    from ({{ cost_allocation_pools('live_runs') }})
    where (run, origin_member) not in (select run, origin_member from rate_origins)
),

stale as (
    select run, main_account, origin_member, 'live run does not equal the current trial balance' as problem
    from sides
    group by run, main_account, origin_member
    having countIf(side = 'published') > 0 and sumIf(pool, side = 'published') != sumIf(pool, side = 'current')
)

select * from stamp_violations
union all
select * from stale
