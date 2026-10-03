{# konsol#305-W3-5 (Deepak Pai, 3 Oct 2026, option C): a balance-sheet pair compares both sides translated at
   the closing rate, so a cross-currency balance difference is judged against the group's tolerance: over it
   'over_tolerance', within it 'within_tolerance'. Its difference_cause stays 'fx'. A P&L (movement) pair
   compares the period at average rates and stays 'fx_difference'. A same-currency booking difference is
   judged as before.

   On the fixture test_fixtures/assert_ic_match_status_cases.sql (group ZZIC, tolerance 10, FY2026 P1):
     - ZZE ZZ2100 <-> ZZP ZZ1100: EUR/USD, balance, difference 40   -> over_tolerance, cause fx;
     - ZZF ZZ2100 <-> ZZS ZZ1100: EUR/USD, balance, difference 4    -> within_tolerance, cause fx;
     - ZZE ZZ5100 <-> ZZP ZZ4100: EUR/USD, movement, difference -80 -> fx_difference, cause fx;
     - ZZP ZZ1100 <-> ZZS ZZ2100: USD/USD, balance, difference 50   -> over_tolerance, cause booking.
   One row per expectation not met; an expected pair that is missing is a row too.

   Without group ZZIC (a site that did not load the fixture) the test has nothing to check and returns no rows. #}

with expectations as (
    select 'ZZE' as ea, 'ZZ2100' as aa, 'ZZP' as eb, 'ZZ1100' as ab, 'balance' as bas, 'fx' as cause, 'over_tolerance' as status
    union all select 'ZZF', 'ZZ2100', 'ZZS', 'ZZ1100', 'balance', 'fx', 'within_tolerance'
    union all select 'ZZE', 'ZZ5100', 'ZZP', 'ZZ4100', 'movement', 'fx', 'fx_difference'
    union all select 'ZZP', 'ZZ1100', 'ZZS', 'ZZ2100', 'balance', 'booking', 'over_tolerance'
),

r as (
    select entity_a, account_a, entity_b, account_b, basis, difference_cause, match_status, difference
    from {{ ref('gold_ic_reconciliation') }}
    where consolidation_group = 'ZZIC' and fiscal_year = 2026 and fiscal_period = 1
),

present as (
    select count() as n from {{ source('epm_gold', 'consolidation_groups') }} where consolidation_group = 'ZZIC'
)

select * from (
    select
        concat(e.ea, ' ', e.aa, ' <-> ', e.eb, ' ', e.ab) as pair,
        concat(r.basis, ' ', r.difference_cause, ' ', r.match_status, ' (difference ', toString(round(r.difference, 2)), ')') as got,
        concat(e.bas, ' ', e.cause, ' ', e.status) as expected
    from expectations as e
    inner join r
        on r.entity_a = e.ea and r.account_a = e.aa and r.entity_b = e.eb and r.account_b = e.ab
    where r.basis != e.bas or r.difference_cause != e.cause or r.match_status != e.status

    union all

    select
        concat(ea, ' ', aa, ' <-> ', eb, ' ', ab) as pair,
        'missing' as got,
        concat(bas, ' ', cause, ' ', status) as expected
    from expectations
    where (ea, aa, eb, ab) not in (select entity_a, account_a, entity_b, account_b from r)
)
where (select n from present) > 0
