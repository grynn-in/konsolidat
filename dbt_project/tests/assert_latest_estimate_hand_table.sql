-- konsol#348 S6 WA7 (FC-2-1, S6-Q2 a): gold_latest_estimate equals a table worked out by hand.
-- The fixture (test_fixtures/assert_latest_estimate_hand_table.sql) declares FY2026 P1-P12 and two
-- approved rounds of forecast scenario ZZ_FC_LE: ZZ-LE-R1 as of 2026-03-31 (P3), horizon 3, and
-- ZZ-LE-R2 as of 2026-06-30 (P6), horizon 6. Each round's estimate is its year's actuals up to and
-- including the as-of period plus its own forecast after the as-of within the horizon, layers summed;
-- an entity the round does not forecast is absent, and a forecast row at or before the as-of is not in
-- the estimate (the actual replaces it). The expected rows are below; a multiset diff (UNION ALL +
-- GROUP BY with +1/-1, never count() over EXCEPT, konsolidat#361) names every row that differs:
-- net +1 expected and missing, -1 produced and not expected. Amounts rounded to 4 places.
-- The expected table is the fixture's, so, like every hand table (assert_budget_ytd_hand_table,
-- assert_budget_consolidated_hand_table), it is vacuous where the fixture's scenario ZZ_FC_LE is absent
-- (every real site, and the full CI build): no expected row is built and only ZZ_FC_LE's produced rows
-- are read. ZZ_FC_LE is present when a Budget Cycle names it (the build-mode fixture, so a model that
-- drops the whole scenario still fails) or when gold_latest_estimate holds it (the test-mode must_flag,
-- which seeds the table directly). It is not a `fixture_only_tests` test: that var is ON in
-- ci_full_build.py's full builds (it marks a costly test, not fixture-shaped expectations), which ran
-- this test there on data without ZZ_FC_LE: 6 expected rows missing.
{{ config(severity='error') }}

with expected as (
    select
        scenario_id as k_scenario,
        cycle as k_cycle,
        data_area_id as k_entity,
        fiscal_year as k_year,
        fiscal_period as k_period,
        main_account as k_account,
        currency as k_currency,
        source as k_source,
        round(amount, 4) as k_amount,
        1 as sign
    from values(
        'scenario_id String, cycle String, data_area_id String, fiscal_year UInt16, fiscal_period UInt8, main_account String, currency String, source String, amount Float64',
        -- R1, as of P3, horizon 3 (P4-P6): actual P3; forecast P4 only (its P3 row is replaced by the
        -- actual, its P7 row is beyond the horizon)
        ('ZZ_FC_LE', 'ZZ-LE-R1', 'ZZE1', 2026, 3, 'ZZ4000', 'USD', 'actual', -30),
        ('ZZ_FC_LE', 'ZZ-LE-R1', 'ZZE1', 2026, 4, 'ZZ4000', 'USD', 'forecast', -40),
        -- R2, as of P6, horizon 6 (P7-P12): actual P3 and P6; forecast P7 (two layers, -71 - 1) and P12
        -- (its P6 row is replaced by the actual)
        ('ZZ_FC_LE', 'ZZ-LE-R2', 'ZZE1', 2026, 3, 'ZZ4000', 'USD', 'actual', -30),
        ('ZZ_FC_LE', 'ZZ-LE-R2', 'ZZE1', 2026, 6, 'ZZ4000', 'USD', 'actual', -60),
        ('ZZ_FC_LE', 'ZZ-LE-R2', 'ZZE1', 2026, 7, 'ZZ4000', 'USD', 'forecast', -72),
        ('ZZ_FC_LE', 'ZZ-LE-R2', 'ZZE1', 2026, 12, 'ZZ4000', 'USD', 'forecast', -120)
    )
    where 'ZZ_FC_LE' in (select scenario_id from {{ source('epm_staging', 'budget_cycles') }})
       or 'ZZ_FC_LE' in (select scenario_id from {{ ref('gold_latest_estimate') }})
),

produced as (
    select
        scenario_id as k_scenario,
        cycle as k_cycle,
        data_area_id as k_entity,
        toUInt16(fiscal_year) as k_year,
        toUInt8(fiscal_period) as k_period,
        toString(main_account) as k_account,
        currency as k_currency,
        source as k_source,
        round(sum(toFloat64(period_amount)), 4) as k_amount,
        -1 as sign
    from {{ ref('gold_latest_estimate') }}
    where scenario_id = 'ZZ_FC_LE'
    group by scenario_id, cycle, data_area_id, fiscal_year, fiscal_period, main_account, currency, source
)

select k_scenario, k_cycle, k_entity, k_year, k_period, k_account, k_currency, k_source, k_amount, sum(sign) as net
from (
    select * from expected
    union all
    select * from produced
)
group by k_scenario, k_cycle, k_entity, k_year, k_period, k_account, k_currency, k_source, k_amount
having net != 0
