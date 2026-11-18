-- konsol#348 S6 WC3 (FC-4-2, S6-Q8 a): gold_forecast_accuracy_group equals a table worked out by hand.
-- The group-currency twin of gold_forecast_accuracy: per consolidation group, the round's translated
-- budget (gold_consolidated_budget_tb.group_amount, at the Cycle's Rate Set, layers summed) against the
-- consolidated actuals (gold_consolidated_trial_balance.group_amount, at the actuals' rates), summed to the
-- budget dimensions, in closed Regular periods after the round's as-of within its horizon, for the
-- entities the round forecasts in that group. The rates differ, so an entity outside the group's currency
-- carries the FX movement in its error; that is the point of a group-currency view. The fixture
-- (test_fixtures/assert_forecast_accuracy_group_hand_table.sql) and its expected rows are below. A
-- multiset diff (UNION ALL + GROUP BY with +1/-1, konsolidat#361) names every row that differs. Amounts
-- rounded to 4 places; the percentage compared as text ('NULL' for NULL).
-- Vacuous where the fixture's scenario ZZ_FC_ACG is absent (every real site, and the full CI build), as
-- assert_forecast_accuracy_hand_table. Not a `fixture_only_tests` test.
{{ config(severity='error') }}

with expected as (
    select
        consolidation_group as k_group,
        scenario_id as k_scenario,
        cycle as k_cycle,
        data_area_id as k_entity,
        fiscal_year as k_year,
        fiscal_period as k_period,
        main_account as k_account,
        reporting_currency as k_currency,
        lag as k_lag,
        round(forecast_amount, 4) as k_forecast,
        round(actual_amount, 4) as k_actual,
        round(forecast_error, 4) as k_error,
        round(forecast_abs_error, 4) as k_abs_error,
        pct as k_pct,
        1 as sign
    from values(
        'consolidation_group String, scenario_id String, cycle String, data_area_id String, fiscal_year UInt16, fiscal_period UInt8, main_account String, reporting_currency String, lag Int32, forecast_amount Float64, actual_amount Float64, forecast_error Float64, forecast_abs_error Float64, pct String',
        -- ZZG (USD), round as of P3, P4 closed (lag 1). ZZE1 (USD): base -45 + challenge -5 vs -40
        ('ZZG', 'ZZ_FC_ACG', 'ZZ-ACG-R1', 'ZZE1', 2026, 4, 'ZZ4000', 'USD', 1, -50, -40, -10, 10, '-25'),
        -- ZZE1: a forecast with no actual (error % NULL); an actual with no forecast (a forecast of 0)
        ('ZZG', 'ZZ_FC_ACG', 'ZZ-ACG-R1', 'ZZE1', 2026, 4, 'ZZ5000', 'USD', 1, 20, 0, 20, 20, 'NULL'),
        ('ZZG', 'ZZ_FC_ACG', 'ZZ-ACG-R1', 'ZZE1', 2026, 4, 'ZZ6000', 'USD', 1, 0, 8, -8, 8, '-100'),
        -- ZZE2 (EUR): local -100 both sides; the budget's set translates at 1.1 (-110), the actuals at 1.2
        -- (-120). The whole error (10) is the FX movement.
        ('ZZG', 'ZZ_FC_ACG', 'ZZ-ACG-R1', 'ZZE2', 2026, 4, 'ZZ4000', 'USD', 1, -110, -120, 10, 10, '8.3333'),
        -- ZZG2 holds ZZE1 proportionally (50%): its own group, never added to ZZG
        ('ZZG2', 'ZZ_FC_ACG', 'ZZ-ACG-R1', 'ZZE1', 2026, 4, 'ZZ4000', 'USD', 1, -25, -20, -5, 5, '-25')
    )
    where 'ZZ_FC_ACG' in (select scenario_id from {{ source('epm_staging', 'budget_cycles') }})
       or 'ZZ_FC_ACG' in (select scenario_id from {{ ref('gold_forecast_accuracy_group') }})
),

produced as (
    select
        consolidation_group as k_group,
        scenario_id as k_scenario,
        cycle as k_cycle,
        data_area_id as k_entity,
        toUInt16(fiscal_year) as k_year,
        toUInt8(fiscal_period) as k_period,
        toString(main_account) as k_account,
        reporting_currency as k_currency,
        toInt32(lag) as k_lag,
        round(sum(toFloat64(forecast_amount)), 4) as k_forecast,
        round(sum(toFloat64(actual_amount)), 4) as k_actual,
        round(sum(toFloat64(forecast_error)), 4) as k_error,
        round(sum(toFloat64(forecast_abs_error)), 4) as k_abs_error,
        if(isNull(any(forecast_error_pct)), 'NULL',
           toString(round(assumeNotNull(any(forecast_error_pct)), 4))) as k_pct,
        -1 as sign
    from {{ ref('gold_forecast_accuracy_group') }}
    where scenario_id = 'ZZ_FC_ACG'
    group by consolidation_group, scenario_id, cycle, data_area_id, fiscal_year, fiscal_period, main_account,
             reporting_currency, lag
)

select k_group, k_scenario, k_cycle, k_entity, k_year, k_period, k_account, k_currency, k_lag,
       k_forecast, k_actual, k_error, k_abs_error, k_pct, sum(sign) as net
from (
    select * from expected
    union all
    select * from produced
)
group by k_group, k_scenario, k_cycle, k_entity, k_year, k_period, k_account, k_currency, k_lag,
         k_forecast, k_actual, k_error, k_abs_error, k_pct
having net != 0
