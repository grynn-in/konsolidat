-- konsol#348 S2 (Q16-c, one writer per grain; decided 13 Nov 2026 under Deepak Pai's standing rule).
-- gold_spread_budget sums manual lines without the cycle, so two Cycles with lines on one
-- (scenario, fiscal year) would be added together: a doubled budget. konsol's intake keeps one Cycle
-- per (scenario, year); this is the warehouse backstop, one row per (scenario, fiscal year) that
-- epm_raw.budget_entries holds under more than one cycle. epm_gold.budget_annual_input carries no
-- cycle column, so the annual side has nothing to check here (n/a).
--
-- konsol#348 S3 B5 (QB8 a): only a forecast scenario has rounds, and each round is its own approved
-- Cycle (Q23 a), so a scenario declared scenario_type 'forecast' in epm_gold.scenario_definitions is
-- expected to hold several cycles per year and is not checked here. Every other scenario is: a budget
-- scenario, and one declared nowhere (assert_scenario_rows_declared names the undeclared one; this
-- test still holds it to one cycle rather than waving it through). The exclusion is a NOT IN, not a
-- join: join_use_nulls=0 fills an unmatched join with '' and would hide the undeclared case.
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
