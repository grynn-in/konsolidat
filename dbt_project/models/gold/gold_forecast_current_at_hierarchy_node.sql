{{
    config(
        materialized='view',
        schema='gold'
    )
}}

{# konsol#348 S6-Q1 (b), decided by Deepak Pai, 17 Nov 2026 (#348 comment 6953756459): the budget
   hierarchy rollup narrowed to each forecast (scenario, fiscal year)'s DECLARED current round.

   gold_budget_at_hierarchy_node carries and groups by `cycle` (S3 B11), so two rounds never sum at a
   node in the table; but konsol's hierarchy read (hierarchy_query, the K.EPM hierarchy forecast read)
   narrows by scenario_id and layer only, never by cycle, and would add them. Its forecast config reads
   THIS view instead. Same columns as the rollup (`select *`).

   The filter is gold_scenario_trial_balance's and gold_forecast_current's: (scenario_id, fiscal_year,
   cycle) in gold_forecast_current_round, IN with a tuple (join_use_nulls=0). A forecast pair with no
   declaration has no row; a budget scenario is read from the rollup itself. If this view is ever slow
   (a join on every hierarchy forecast read), materialise it as a table in the scenarios domain; the
   name konsol reads does not change. #}

select *
from {{ ref('gold_budget_at_hierarchy_node') }}
where (scenario_id, toUInt16(fiscal_year), cycle) in (
    select scenario_id, toUInt16(fiscal_year), cycle
    from {{ ref('gold_forecast_current_round') }}
)
