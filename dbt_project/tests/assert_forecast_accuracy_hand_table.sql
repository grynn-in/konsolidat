-- konsol#348 S6 WC2 (FC-4-2, S6-Q8 a): gold_forecast_accuracy equals a table worked out by hand.
-- Per approved forecast round, per CLOSED Regular period after its as-of period within its horizon
-- (epm_staging.fiscal_periods.status Closed or Locked, the effective status konsol publishes), per
-- entity the round forecasts, account, budget dimensions and currency: the forecast (layers summed),
-- the actual, error = forecast - actual, |error|, error % = error / |actual| x 100 (NULL when the actual
-- is 0) and the lag in declared Regular periods from the as-of period. The fixture
-- (test_fixtures/assert_forecast_accuracy_hand_table.sql) has round R1 as of P3 (horizon 9) and R2 as of
-- P5 (horizon 2), P1-P6 closed and P7 onwards open; the expected rows are below. A multiset diff (UNION
-- ALL + GROUP BY with +1/-1, never count() over EXCEPT, konsolidat#361) names every row that differs:
-- net +1 expected and missing, -1 produced and not expected. Amounts rounded to 4 places; the
-- percentage is compared as text so a NULL is a value of its own ('NULL').
-- Vacuous where the fixture's scenario ZZ_FC_ACC is absent (every real site, and the full CI build): no
-- expected row is built and only ZZ_FC_ACC's produced rows are read. ZZ_FC_ACC is present when a Budget
-- Cycle names it (the build-mode fixture, so a model that drops the whole scenario still fails) or when
-- gold_forecast_accuracy holds it (the test-mode must_flag). Not a `fixture_only_tests` test (see
-- assert_latest_estimate_hand_table).
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
        -- R1, as of P3: P4 (lag 1) revenue, base -40 + challenge -2 against -45
        ('ZZ_FC_ACC', 'ZZ-ACC-R1', 'ZZE1', 2026, 4, 'ZZ4000', 'USD', 1, -42, -45, 3, 3, '6.6667'),
        -- R1 P4: an account the round did not forecast is a forecast of zero (no budget = budget zero)
        ('ZZ_FC_ACC', 'ZZ-ACC-R1', 'ZZE1', 2026, 4, 'ZZ6000', 'USD', 1, 0, 10, -10, 10, '-100'),
        -- R1 P5 (lag 2): exact, and a cost forecast with no actual (error % NULL)
        ('ZZ_FC_ACC', 'ZZ-ACC-R1', 'ZZE1', 2026, 5, 'ZZ4000', 'USD', 2, -50, -50, 0, 0, '0'),
        ('ZZ_FC_ACC', 'ZZ-ACC-R1', 'ZZE1', 2026, 5, 'ZZ5000', 'USD', 2, 20, 0, 20, 20, 'NULL'),
        -- R1 P6 (lag 3, a Locked period); P7 onwards are Open: no row
        ('ZZ_FC_ACC', 'ZZ-ACC-R1', 'ZZE1', 2026, 6, 'ZZ4000', 'USD', 3, -60, -55, -5, 5, '-9.0909'),
        -- R2, as of P5, horizon 2: P6 (lag 1); P7 is Open, P8 beyond the horizon
        ('ZZ_FC_ACC', 'ZZ-ACC-R2', 'ZZE1', 2026, 6, 'ZZ4000', 'USD', 1, -66, -55, -11, 11, '-20')
    )
    where 'ZZ_FC_ACC' in (select scenario_id from {{ source('epm_staging', 'budget_cycles') }})
       or 'ZZ_FC_ACC' in (select scenario_id from {{ ref('gold_forecast_accuracy') }})
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
    where scenario_id = 'ZZ_FC_ACC'
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
