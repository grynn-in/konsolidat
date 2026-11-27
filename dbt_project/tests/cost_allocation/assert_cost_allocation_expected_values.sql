-- The worked examples' values are asserted (konsol#269, RF5, review finding 5; 2b-2
-- W5). Conservation and per-account balance hold for any correct-looking set of
-- coefficients, Step-Down's included; only the numbers tell Reciprocal apart, or a
-- rate charged from a pool split. The expected values below belong to fixture runs:
--   ZZEV  RC6 reciprocal coefficients, pools IT 1,000 and HR 400, Declared Allocation
--         Account: Sales 885, Ops 515, IT 0, HR 0; IT -> HR 725 = own 500 + pass 225.
--   ZZEW  Step-Down coefficients under the same expectations (must flag).
--   ZZER  the declared-rate example (plan section 3), Step-Down: IT charges 50 per
--         ticket (HR 5, Sales 8, Ops 6), HR splits 400 + 250 by 5/8 : 3/8. On the
--         allocation account: Sales 806.25, Ops 543.75, IT -950 (its relief), HR 0;
--         IT -> HR own 250, HR -> Sales pass 156.25.
--   ZZEQ  the declared-rate example under Reciprocal, with FM (pool 300, by area
--         HR 5, IT 1, Sales 1, Ops 1) and HR by headcount FM 4, Sales 1: Sales 940,
--         Ops 505, IT -745 (205 received - 950 charged), HR 0, FM 0; IT -> HR own
--         250; FM -> IT own 37.5 (FM's pool) and pass 167.5 (IT's returning
--         ticket 50, HR's 80, FM's returning 37.5): the 205 that stops at IT.
-- The names are fixture data, so the test is enabled only under the fixture gate
-- (var fixture_only_tests, which scripts/fixture_gate.py passes to a fixture that
-- names the test); on a real site it does not exist, so a run named ZZEV there
-- cannot fail it. Rows returned are violations:
--   net:<member>      the member's net on the run's allocation account
--   gross:<s>><r>:<k> received lines from sender s at receiver r of hop kind k
-- Expected and actual are summed per run and key side by side: a missing or a
-- wrong number differs. UNION ALL + GROUP BY, no join
-- (join_use_nulls=0 would fill a missing side with 0).
{{ config(enabled=var('fixture_only_tests', false)) }}
with expected as (
    select tupleElement(x.m, 1) as run, tupleElement(x.m, 2) as metric, toDecimal128(tupleElement(x.m, 3), 16) as expected_value
    from (
        select arrayJoin([
            ('ZZEV', 'net:ZZSA', 885), ('ZZEV', 'net:ZZOP', 515), ('ZZEV', 'net:ZZIT', 0), ('ZZEV', 'net:ZZHR', 0),
            ('ZZEV', 'gross:ZZIT>ZZHR:own', 500), ('ZZEV', 'gross:ZZIT>ZZHR:pass', 225),
            ('ZZEW', 'net:ZZSA', 885), ('ZZEW', 'net:ZZOP', 515), ('ZZEW', 'net:ZZIT', 0), ('ZZEW', 'net:ZZHR', 0),
            ('ZZEW', 'gross:ZZIT>ZZHR:own', 500), ('ZZEW', 'gross:ZZIT>ZZHR:pass', 225),
            ('ZZER', 'net:ZZSA', 806.25), ('ZZER', 'net:ZZOP', 543.75), ('ZZER', 'net:ZZIT', -950), ('ZZER', 'net:ZZHR', 0),
            ('ZZER', 'gross:ZZIT>ZZHR:own', 250), ('ZZER', 'gross:ZZHR>ZZSA:pass', 156.25),
            ('ZZEQ', 'net:ZZSA', 940), ('ZZEQ', 'net:ZZOP', 505), ('ZZEQ', 'net:ZZIT', -745), ('ZZEQ', 'net:ZZHR', 0),
            ('ZZEQ', 'net:ZZFM', 0), ('ZZEQ', 'gross:ZZIT>ZZHR:own', 250),
            ('ZZEQ', 'gross:ZZFM>ZZIT:own', 37.5), ('ZZEQ', 'gross:ZZFM>ZZIT:pass', 167.5)]) as m
    ) as x
    where run in (select name from {{ source('epm_staging', 'cost_allocation_runs') }})
),

runs as (
    select name, allocation_account
    from {{ source('epm_staging', 'cost_allocation_runs') }}
    where name in ('ZZEV', 'ZZEW', 'ZZER', 'ZZEQ')
),

actual as (
    select l.run as run, concat('net:', l.member) as metric, sum(l.amount) as value
    from {{ ref('gold_cost_allocation') }} as l
    inner join runs as r on r.name = l.run and r.allocation_account = l.main_account
    group by run, metric

    union all

    select run, concat('gross:', sender_member, '>', receiver_member, ':', hop_kind), sum(amount)
    from {{ ref('gold_cost_allocation') }}
    where run in ('ZZEV', 'ZZEW', 'ZZER', 'ZZEQ') and line_type = 'received'
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
