-- konsol#348 S6 WA7: gold_latest_estimate has one row per (scenario_id, cycle, data_area_id,
-- fiscal_year, fiscal_period, main_account, budget dimensions, currency). A second row on a key is an
-- actual and a forecast for the same period of one round (the as-of split failed) or a grain the
-- model's group by missed; either way a K.EPM read of the latest estimate would add them. Error
-- severity. Fixtures: assert_latest_estimate_hand_table.sql (pass, build mode),
-- assert_latest_estimate_grain_unique.must_flag.sql (an actual and a forecast row on one key: 1).
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
    groupArray(source) as sources,
    count() as rows_on_key
from {{ ref('gold_latest_estimate') }}
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
