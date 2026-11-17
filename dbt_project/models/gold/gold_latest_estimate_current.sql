{{
    config(
        materialized='view',
        schema='gold'
    )
}}

{# konsol#348 S6-Q1 (b), decided by Deepak Pai, 17 Nov 2026 (#348 comment 6953756459), and S6-Q2 (a):
   the latest estimate of each forecast (scenario, fiscal year)'s DECLARED current round.

   gold_latest_estimate keeps every approved round side by side (keyed by `cycle`). konsol's
   `latest_estimate` Dataset (the Excel K.EPM latest-estimate read) binds scenario_id but never cycle,
   so it reads THIS view: the same columns (`select *`), the declared round's rows only. A round's
   rows are inside its own fiscal year, so the filter is gold_scenario_trial_balance's and
   gold_forecast_current's: (scenario_id, fiscal_year, cycle) in gold_forecast_current_round, IN with a
   tuple (join_use_nulls=0). A forecast year with no declaration reads nothing here
   (assert_forecast_year_has_current_round WARNs naming it). #}

select *
from {{ ref('gold_latest_estimate') }}
where (scenario_id, toUInt16(fiscal_year), cycle) in (
    select scenario_id, toUInt16(fiscal_year), cycle
    from {{ ref('gold_forecast_current_round') }}
)
