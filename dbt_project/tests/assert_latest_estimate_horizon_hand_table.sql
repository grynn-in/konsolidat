-- konsolidat#376 (konsol#348 Q24 a): gold_latest_estimate cuts a forecast round at the ROUND's horizon,
-- the same horizon gold_forecast_accuracy measures it to. A round is (scenario_id, as_of_date): every
-- approved Cycle sharing the as-of, one per fiscal year the horizon touches (Q24 a). Its horizon is the
-- LONGEST horizon_periods among those Cycles (forecast_rounds(), macros/forecast_rounds.sql, the one
-- definition both models read); a Cycle's own shorter horizon does not cut the round short. Worked out by
-- hand on the horizon fixture (test_fixtures/assert_forecast_accuracy_horizon_hand_table.sql): round A
-- as of 2026-09-30 (FY2026 P9) has a FY2026 Cycle at horizon 12 and a FY2027 Cycle at horizon 3, so its
-- FY2027 forecast P1-P4 (lags 4-7) is in the estimate; cut at the FY2027 Cycle's own 3 it was missing,
-- while accuracy measured the same periods. Round B as of 2026-12-31 (FY2026 P12, horizon 2) keeps
-- FY2027 P1-P2; P3 (lag 3) is beyond. Each Cycle's estimate stays in its own fiscal year, and a forecast
-- row at or before the as-of is replaced by the actual. The multiset diff and rounding are
-- assert_latest_estimate_hand_table's (UNION ALL + GROUP BY, never count() over EXCEPT, konsolidat#361).
-- Vacuous where the fixture's scenario ZZ_FC_HZN is absent (every real site, and the full CI build): no
-- expected row is built and only ZZ_FC_HZN's produced rows are read. ZZ_FC_HZN is present when a Budget
-- Cycle names it (the build-mode fixture) or when gold_latest_estimate holds it (the test-mode
-- must_flag). Not a `fixture_only_tests` test (see assert_latest_estimate_hand_table).
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
        -- Round A (as of FY2026 P9), FY2026 Cycle: the P9 actual (its P9 forecast is replaced), forecast P10-P12
        ('ZZ_FC_HZN', 'ZZ-HZN-A26', 'ZZH1', 2026, 9, 'ZZ4000', 'USD', 'actual', -95),
        ('ZZ_FC_HZN', 'ZZ-HZN-A26', 'ZZH1', 2026, 10, 'ZZ4000', 'USD', 'forecast', -100),
        ('ZZ_FC_HZN', 'ZZ-HZN-A26', 'ZZH1', 2026, 11, 'ZZ4000', 'USD', 'forecast', -110),
        ('ZZ_FC_HZN', 'ZZ-HZN-A26', 'ZZH1', 2026, 12, 'ZZ4000', 'USD', 'forecast', -120),
        -- Round A, FY2027 Cycle (own horizon 3, the round's 12): forecast FY2027 P1-P4 at lags 4-7; no
        -- FY2027 period is at or before the as-of, so no actual
        ('ZZ_FC_HZN', 'ZZ-HZN-A27', 'ZZH1', 2027, 1, 'ZZ4000', 'USD', 'forecast', -10),
        ('ZZ_FC_HZN', 'ZZ-HZN-A27', 'ZZH1', 2027, 2, 'ZZ4000', 'USD', 'forecast', -20),
        ('ZZ_FC_HZN', 'ZZ-HZN-A27', 'ZZH1', 2027, 3, 'ZZ4000', 'USD', 'forecast', -30),
        ('ZZ_FC_HZN', 'ZZ-HZN-A27', 'ZZH1', 2027, 4, 'ZZ4000', 'USD', 'forecast', -40),
        -- Round B (as of FY2026 P12, horizon 2): forecast FY2027 P1-P2; P3 (lag 3) is beyond the horizon
        ('ZZ_FC_HZN', 'ZZ-HZN-B27', 'ZZH1', 2027, 1, 'ZZ4000', 'USD', 'forecast', -12),
        ('ZZ_FC_HZN', 'ZZ-HZN-B27', 'ZZH1', 2027, 2, 'ZZ4000', 'USD', 'forecast', -18)
    )
    where 'ZZ_FC_HZN' in (select scenario_id from {{ source('epm_staging', 'budget_cycles') }})
       or 'ZZ_FC_HZN' in (select scenario_id from {{ ref('gold_latest_estimate') }})
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
    where scenario_id = 'ZZ_FC_HZN'
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
