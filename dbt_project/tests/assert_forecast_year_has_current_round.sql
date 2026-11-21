-- konsol#348 S6-Q1 (b), decided by Deepak Pai, 17 Nov 2026 (#348 comment 6953756459): a forecast
-- (scenario, fiscal year) with approved rounds and NO Current Forecast declaration has no forecast rows
-- anywhere. gold_forecast_current_round holds only declared pairs, and every forecast reader joins it, so
-- an undeclared year reads EMPTY (never the sum of its rounds, never the latest round: FC-3-1 rejected
-- "latest wins"). Empty is correct and deliberate, but it is a reporting gap the user must see, so this
-- names every such pair with its approved rounds: declare one in konsol (Planning > Current Forecasts).
--
-- Approved rounds are the budget_cycles rows (konsol syncs submitted Cycles only) of a scenario declared
-- scenario_type 'forecast' in epm_gold.scenario_definitions; a budget scenario has no rounds and is not
-- read here (Approved Budget is its declaration, assert_budget_one_cycle_per_scenario_year its rule).
-- A declaration whose Cycle is cancelled or belongs to another pair leaves the pair without a row in
-- gold_forecast_current_round and is named here too (the model joins budget_cycles on the pair as well
-- as on the name). IN / NOT IN, not joins: join_use_nulls=0 would fill an unmatched join with ''.
-- WARN, not error: the actuals and the budget still build; the gap is a declaration the user owes.
-- Fixtures: assert_forecast_year_has_current_round.must_flag.sql (two approved rounds, no declaration:
-- 1 result), gold_forecast_current_round.two_rounds.sql (declared: pass).
{{ config(severity='warn') }}

select
    bc.scenario_id as scenario_id,
    bc.fiscal_year as fiscal_year,
    groupArray(bc.name) as approved_rounds,
    count() as approved_round_count
from {{ source('epm_staging', 'budget_cycles') }} as bc
where bc.scenario_id in (
    select scenario_id
    from {{ source('epm_gold', 'scenario_definitions') }}
    where scenario_type = 'forecast'
)
  and (bc.scenario_id, bc.fiscal_year) not in (
    select scenario_id, fiscal_year
    from {{ ref('gold_forecast_current_round') }}
)
group by bc.scenario_id, bc.fiscal_year
order by bc.scenario_id, bc.fiscal_year
