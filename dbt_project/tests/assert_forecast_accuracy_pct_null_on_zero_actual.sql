-- konsol#348 S6 WC2: the error percentage of gold_forecast_accuracy is NULL exactly when the actual is
-- 0, and otherwise is forecast_error / |actual_amount| x 100 (the sign of the error, the scale of the
-- actual; variance_pct's convention). A percentage of a zero actual has no value: 0 would read as a
-- perfect forecast and an infinity would break every average, so it is NULL and the report shows "n/a".
-- One row per breach: a non-NULL percentage on a zero actual, a NULL on a non-zero one, or a value off
-- the formula by more than 0.0001 percentage points. Error severity. Fixtures:
-- assert_forecast_accuracy_hand_table.sql (pass, build mode, one zero actual),
-- assert_forecast_accuracy_pct_null_on_zero_actual.must_flag.sql (a 0 on a zero actual and a NULL on a
-- non-zero one: 2).
{{ config(severity='error') }}

select
    scenario_id,
    cycle,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    actual_amount,
    forecast_error,
    forecast_error_pct
from {{ ref('gold_forecast_accuracy') }}
where (actual_amount = 0 and forecast_error_pct is not null)
   or (actual_amount != 0 and forecast_error_pct is null)
   or (actual_amount != 0
       and abs(assumeNotNull(forecast_error_pct)
               - toFloat64(forecast_error) / abs(toFloat64(actual_amount)) * 100) > 0.0001)
