-- konsol#348 S6 WC2 review (m1, m2): gold_forecast_accuracy measures a round to the ROUND's horizon, and
-- counts the lag across a year end, worked out by hand. A round is (scenario_id, as_of_date): every
-- approved Cycle sharing the as-of (Q24 a, one Cycle per fiscal year). Its horizon is the LONGEST
-- horizon_periods among those Cycles, as konsol's horizon_coverage_model counts the round's coverage; a
-- Cycle's own shorter horizon does not cut the round short. The lag is in declared Regular periods from
-- the as-of period, so the first period of the next year is lag 1 for an as-of in the last period of the
-- year before. The fixture (test_fixtures/assert_forecast_accuracy_horizon_hand_table.sql) has round A as
-- of 2026-09-30 (FY2026 P9: FY2026 Cycle horizon 12, FY2027 Cycle horizon 3) and round B as of 2026-12-31
-- (FY2026 P12: FY2027 Cycle horizon 2); FY2026 and FY2027 P1-P3 closed, FY2027 P4 onwards open. The
-- multiset diff, rounding and NULL text are assert_forecast_accuracy_hand_table's.
-- Vacuous where the fixture's scenario ZZ_FC_HZN is absent (every real site, and the full CI build): no
-- expected row is built and only ZZ_FC_HZN's produced rows are read. ZZ_FC_HZN is present when a Budget
-- Cycle names it (the build-mode fixture) or when gold_forecast_accuracy holds it (the test-mode
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
        lag as k_lag,
        round(forecast_amount, 4) as k_forecast,
        round(actual_amount, 4) as k_actual,
        round(forecast_error, 4) as k_error,
        round(forecast_abs_error, 4) as k_abs_error,
        pct as k_pct,
        1 as sign
    from values(
        'scenario_id String, cycle String, data_area_id String, fiscal_year UInt16, fiscal_period UInt8, main_account String, currency String, lag Int32, forecast_amount Float64, actual_amount Float64, forecast_error Float64, forecast_abs_error Float64, pct String',
        -- Round A (as of FY2026 P9), FY2026 Cycle: P10-P12 at lags 1-3
        ('ZZ_FC_HZN', 'ZZ-HZN-A26', 'ZZH1', 2026, 10, 'ZZ4000', 'USD', 1, -100, -105, 5, 5, '4.7619'),
        ('ZZ_FC_HZN', 'ZZ-HZN-A26', 'ZZH1', 2026, 11, 'ZZ4000', 'USD', 2, -110, -110, 0, 0, '0'),
        ('ZZ_FC_HZN', 'ZZ-HZN-A26', 'ZZH1', 2026, 12, 'ZZ4000', 'USD', 3, -120, -100, -20, 20, '-20'),
        -- Round A, FY2027 Cycle (own horizon 3, the round's 12): FY2027 P1-P3 at lags 4-6; P4 is Open
        ('ZZ_FC_HZN', 'ZZ-HZN-A27', 'ZZH1', 2027, 1, 'ZZ4000', 'USD', 4, -10, -15, 5, 5, '33.3333'),
        ('ZZ_FC_HZN', 'ZZ-HZN-A27', 'ZZH1', 2027, 2, 'ZZ4000', 'USD', 5, -20, -20, 0, 0, '0'),
        ('ZZ_FC_HZN', 'ZZ-HZN-A27', 'ZZH1', 2027, 3, 'ZZ4000', 'USD', 6, -30, -24, -6, 6, '-25'),
        -- Round B (as of FY2026 P12, horizon 2): FY2027 P1 is lag 1, P2 lag 2; P3 (lag 3) beyond the horizon
        ('ZZ_FC_HZN', 'ZZ-HZN-B27', 'ZZH1', 2027, 1, 'ZZ4000', 'USD', 1, -12, -15, 3, 3, '20'),
        ('ZZ_FC_HZN', 'ZZ-HZN-B27', 'ZZH1', 2027, 2, 'ZZ4000', 'USD', 2, -18, -20, 2, 2, '10')
    )
    where 'ZZ_FC_HZN' in (select scenario_id from {{ source('epm_staging', 'budget_cycles') }})
       or 'ZZ_FC_HZN' in (select scenario_id from {{ ref('gold_forecast_accuracy') }})
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
        toInt32(lag) as k_lag,
        round(sum(toFloat64(forecast_amount)), 4) as k_forecast,
        round(sum(toFloat64(actual_amount)), 4) as k_actual,
        round(sum(toFloat64(forecast_error)), 4) as k_error,
        round(sum(toFloat64(forecast_abs_error)), 4) as k_abs_error,
        if(isNull(any(forecast_error_pct)), 'NULL',
           toString(round(assumeNotNull(any(forecast_error_pct)), 4))) as k_pct,
        -1 as sign
    from {{ ref('gold_forecast_accuracy') }}
    where scenario_id = 'ZZ_FC_HZN'
    group by scenario_id, cycle, data_area_id, fiscal_year, fiscal_period, main_account, currency, lag
)

select k_scenario, k_cycle, k_entity, k_year, k_period, k_account, k_currency, k_lag,
       k_forecast, k_actual, k_error, k_abs_error, k_pct, sum(sign) as net
from (
    select * from expected
    union all
    select * from produced
)
group by k_scenario, k_cycle, k_entity, k_year, k_period, k_account, k_currency, k_lag,
         k_forecast, k_actual, k_error, k_abs_error, k_pct
having net != 0
