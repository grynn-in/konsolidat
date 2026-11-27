-- Frozen absorption rows whose pool no longer matches the trial balance (konsol#269
-- 2b-2 W7). A Freeze at Approval run keeps the variance it was approved at
-- (gold_cost_allocation_absorption_frozen: pool at approval); if the rate sender's
-- balance on the run's accounts has since changed in gold_scenario_trial_balance, the
-- frozen variance differs from what the same run would show today by that change. One
-- row per frozen run x rate sender. Warn, not error: a frozen run is meant to differ
-- from later data; this tells the accountant it has. It is the absorption twin of
-- assert_cost_allocation_frozen_drift, which judges share origins' lines and leaves
-- rate origins out (their pool is in no line).
-- The current pool is the macro's own (cost_allocation_pools, summed over the run's
-- accounts), and the rate senders are the macro's own (cost_allocation_rate_origins), so
-- the rule is not written twice. Both directions are judged: a frozen row whose sender
-- has lost its trial balance (current 0), and a rate sender with a pool today and no
-- frozen row. UNION ALL + GROUP BY, not a join: join_use_nulls=0 would fill a missing
-- side with 0.
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
    select run, sender_member, pool, 'frozen' as side
    from {{ ref('gold_cost_allocation_absorption_frozen') }}

    union all

    select p.run, p.origin_member, p.origin_amount, 'current' as side
    from ({{ cost_allocation_pools('runs') }}) as p
    where (p.run, p.origin_member) in (select run, origin_member from rate_origins)
)

select
    run,
    sender_member,
    sumIf(pool, side = 'frozen') as frozen_pool,
    sumIf(pool, side = 'current') as current_pool
from sides
group by run, sender_member
having frozen_pool != current_pool
