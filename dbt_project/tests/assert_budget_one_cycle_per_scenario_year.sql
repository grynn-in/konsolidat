-- konsol#348 S2 (Q16-c, one writer per grain; decided 13 Nov 2026 under Deepak Pai's standing rule).
-- A budget-type scenario has one Cycle per (scenario, fiscal year): konsol's intake keeps it so, and this
-- is the warehouse backstop, one row per (scenario, fiscal year) that epm_raw.budget_entries holds under
-- more than one cycle. Since S3 B4 the fact carries the cycle and keeps two cycles apart, so a second
-- cycle no longer doubles the budget; it is still a policy breach, and still named here. The annual side
-- (epm_gold.budget_annual_input, with `cycle` since B3w) is not read here.
--
-- konsol#348 S3 B5 (QB8 a): only a forecast scenario has rounds, and each round is its own approved
-- Cycle (Q23 a), so a scenario declared scenario_type 'forecast' in epm_gold.scenario_definitions is
-- expected to hold several cycles per year and is not checked here. Every other scenario is: a budget
-- scenario, and one declared nowhere (assert_scenario_rows_declared names the undeclared one; this
-- test still holds it to one cycle rather than waving it through). The exclusion is a NOT IN, not a
-- join: join_use_nulls=0 fills an unmatched join with '' and would hide the undeclared case.
-- Since S6 (konsol#348 S6-Q1 b, Deepak Pai, 17 Nov 2026) a forecast's approved rounds sit side by side
-- and every reader takes the declared current round (gold_forecast_current_round); the interim
-- one-approved-round test left with konsol's refusal.
-- Error severity: the budget fact would be wrong.
{{ config(severity='error') }}

select
    scenario_id,
    fiscal_year,
    groupUniqArray(cycle) as cycles
from {{ source('budget_raw', 'budget_entries') }}
where scenario_id not in (
    select scenario_id
    from {{ source('epm_gold', 'scenario_definitions') }}
    where scenario_type = 'forecast'
)
group by scenario_id, fiscal_year
having uniqExact(cycle) > 1
