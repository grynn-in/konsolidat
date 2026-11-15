-- The worked example's values are asserted (konsol#269, RF5, review finding 5).
-- Conservation and per-account balance hold for any correct-looking set of
-- coefficients, Step-Down's included; only the numbers tell Reciprocal apart.
-- The expected values below belong to the fixture runs ZZEV (RC6 reciprocal
-- coefficients, pools IT 1,000 and HR 400, Declared Allocation Account) and ZZEW
-- (Step-Down coefficients, must flag); a site has no run of that name, so this
-- test returns nothing there (it judges a run only where the run exists). Rows returned are violations:
--   net:<member>      the member's net on the run's allocation account
--   gross:<s>><r>:<k> received lines from sender s at receiver r of hop kind k
-- Expected: Sales 885, Ops 515, IT 0, HR 0; IT -> HR 725 = own 500 + pass 225.
-- Expected and actual are summed per run and key side by side: a missing or a
-- wrong number differs. UNION ALL + GROUP BY, no join
-- (join_use_nulls=0 would fill a missing side with 0).
with expected as (
    select r.run as run, tupleElement(x.m, 1) as metric, toDecimal128(tupleElement(x.m, 2), 16) as expected_value
    from (
        select name as run
        from {{ source('epm_staging', 'cost_allocation_runs') }}
        where name in ('ZZEV', 'ZZEW')
    ) as r
    cross join (
        select arrayJoin([
            ('net:ZZSA', 885), ('net:ZZOP', 515), ('net:ZZIT', 0), ('net:ZZHR', 0),
            ('gross:ZZIT>ZZHR:own', 500), ('gross:ZZIT>ZZHR:pass', 225)]) as m
    ) as x
),

runs as (
    select name, allocation_account
    from {{ source('epm_staging', 'cost_allocation_runs') }}
    where name in ('ZZEV', 'ZZEW')
),

actual as (
    select l.run as run, concat('net:', l.member) as metric, sum(l.amount) as value
    from {{ ref('gold_cost_allocation') }} as l
    inner join runs as r on r.name = l.run and r.allocation_account = l.main_account
    group by run, metric

    union all

    select run, concat('gross:', sender_member, '>', receiver_member, ':', hop_kind), sum(amount)
    from {{ ref('gold_cost_allocation') }}
    where run in ('ZZEV', 'ZZEW') and line_type = 'received'
    group by run, sender_member, receiver_member, hop_kind
),

compared as (
    select run, metric, sum(want) as want, sum(got) as got
    from (
        select run, metric, expected_value as want, toDecimal128(0, 16) as got from expected
        union all
        select a.run, a.metric, toDecimal128(0, 16), a.value
        from actual as a
        where (a.run, a.metric) in (select run, metric from expected)
    )
    group by run, metric
)

select run, metric, want as expected_value, got as actual_value
from compared
where want != got
