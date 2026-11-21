{{
    config(
        materialized='view',
        schema='gold'
    )
}}

{# konsol#348 S6-Q1 (b), decided by Deepak Pai, 17 Nov 2026 (#348 comment 6953756459): the forecast fact
   narrowed to each forecast (scenario, fiscal year)'s DECLARED current round.

   gold_spread_budget keeps every approved round side by side (keyed by `cycle`; FC-4 needs them for
   accuracy). A read that does not pick a round sums them, so konsol's `forecast_input` Dataset (the
   Excel K.EPM flat forecast read, which binds scenario_id and layer but never cycle) reads THIS view
   instead. Same columns as the fact (`select *`), so the Dataset's columns do not change.

   The filter is the one gold_scenario_trial_balance uses: the row's (scenario_id, fiscal_year, cycle)
   is in gold_forecast_current_round. IN with a tuple, not a join (join_use_nulls=0 fills an unmatched
   join with ''). Only forecast-type scenarios are in the current-round table, so a budget scenario has
   no row here: a budget is read from the fact, as before. A forecast pair with no declaration has no
   row (never summed, never guessed; assert_forecast_year_has_current_round WARNs naming it).
   assert_forecast_current_ties_to_fact ties the view to the fact per declared round. #}

select *
from {{ ref('gold_spread_budget') }}
where (scenario_id, toUInt16(fiscal_year), cycle) in (
    select scenario_id, toUInt16(fiscal_year), cycle
    from {{ ref('gold_forecast_current_round') }}
)
