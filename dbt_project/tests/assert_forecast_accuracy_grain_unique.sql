-- konsol#348 S6 WC2: gold_forecast_accuracy has one row per (scenario_id, cycle, data_area_id,
-- fiscal_year, fiscal_period, main_account, budget dimensions, currency). A second row on a key means
-- the forecast and the actual of one key did not meet (each side on a row of its own, so the error is
-- wrong on both) or a grain the model's group by missed; a K.EPM read or the Forecast Accuracy report
-- would add them. Error severity. Fixtures: assert_forecast_accuracy_hand_table.sql (pass, build mode),
-- assert_forecast_accuracy_grain_unique.must_flag.sql (the two sides of one key on two rows: 1).
{{ config(severity='error') }}

select
    scenario_id,
    cycle,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    {{ dim_select(dims=get_budget_dimensions(), trailing=true) }}
    currency,
    count() as rows_on_key
from {{ ref('gold_forecast_accuracy') }}
group by
    scenario_id,
    cycle,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    {{ dim_group_by(dims=get_budget_dimensions(), trailing=true) }}
    currency
having count() > 1
