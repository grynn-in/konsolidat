{{
    config(
        materialized='table',
        engine='MergeTree()',
        order_by='(scenario_id, fiscal_year)'
    )
}}

{# konsol#348 S6-Q1 (b), decided by Deepak Pai, 17 Nov 2026 (#348 comment 6953756459): THE current
   round of each forecast (scenario, fiscal year), one row per declared pair.

   A forecast scenario holds several approved rounds per year side by side (Q23 a: a round is a
   Budget Cycle keyed by its as-of date; FC-4 keeps them for accuracy), and rounds must never sum.
   Every entity-grain forecast reader therefore joins THIS table on (scenario_id, fiscal_year,
   cycle) and reads one round: gold_scenario_trial_balance (the budget branch, WA4),
   gold_forecast_current and gold_forecast_current_at_hierarchy_node (the Excel flat and hierarchy
   reads, WA6), gold_latest_estimate_current (WA8), and through them the cost-allocation pool.

   The round is DECLARED, not derived: konsol's Current Forecast doctype (submittable; submit is the
   approval) writes a submitted declaration through to epm_staging.current_forecasts. FC-3-1
   (Deepak Pai, 13 Nov 2026) rejected "latest round wins", so no as-of ordering is read here; a pair
   with approved rounds and no declaration has NO row, every reader is empty for it, and
   assert_forecast_year_has_current_round WARNs naming the pair and its rounds.

   Joins:
   - epm_staging.budget_cycles on the Cycle's name AND the pair (scenario_id, fiscal_year): the
     declaration carries the pair itself, and konsol refuses a Cycle of another scenario or year, so
     the pair match is a sync-drift guard, never a second rule. A declaration whose Cycle is cancelled
     (gone from budget_cycles) or renamed yields no row, and the WARN names the pair.
   - epm_gold.scenario_definitions on scenario_type = 'forecast' (IN, not a join: join_use_nulls=0
     fills an unmatched join with ''). konsol refuses a declaration on any other type; this keeps a
     scenario re-typed afterwards out of the forecast readers. No is_active filter: an inactive
     scenario's declaration stands until it is cancelled, as a budget scenario's Cycle does in
     gold_scenario_trial_balance.
   The Cycle's as_of_date, horizon_periods and rate_set ride along from budget_cycles (the one
   source; the declaration's as_of_date copy is not read), so the readers that count the horizon
   (forecast_round_periods(), gold_latest_estimate) need no second join.
   assert_forecast_current_round_unique (error) pins one row per pair. #}

select
    cf.scenario_id as scenario_id,
    cf.fiscal_year as fiscal_year,
    cf.cycle as cycle,
    bc.as_of_date as as_of_date,
    bc.horizon_periods as horizon_periods,
    bc.rate_set as rate_set
from {{ source('epm_staging', 'current_forecasts') }} as cf
inner join {{ source('epm_staging', 'budget_cycles') }} as bc
    on bc.name = cf.cycle
    and bc.scenario_id = cf.scenario_id
    and bc.fiscal_year = cf.fiscal_year
where cf.scenario_id in (
    select scenario_id
    from {{ source('epm_gold', 'scenario_definitions') }}
    where scenario_type = 'forecast'
)
