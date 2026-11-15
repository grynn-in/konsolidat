-- INTERIM RULE, REMOVED IN S6 (konsol#348, review of grynn-in/konsol#540 / konsolidat#362, 15 Nov 2026).
-- A forecast (scenario, fiscal year) holds at most ONE approved round for now. Four readers still sum a
-- forecast's rounds across the cycle: gold_scenario_trial_balance (its GROUP BY leaves `cycle` out), the
-- cost-allocation pool (konsol cost_allocation_run.py), the forecast_input Dataset (konsol
-- defaults/dataset.json) and hierarchy_query. Two approved rounds in one year would therefore add two
-- forecasts together silently. konsol refuses the second Approve by name (Budget Cycle.before_submit, under
-- the pair lock); this is the warehouse backstop, one row per forecast (scenario, fiscal year) that
-- gold_spread_budget holds under more than one distinct cycle. The fact carries only approved Cycles
-- (konsol syncs docstatus 1), so a second cycle here IS a second approved round.
--
-- Forecasts only, by the declared type in epm_gold.scenario_definitions, as assert_budget_one_cycle_per_
-- scenario_year (B5) does for the budget side: that test leaves forecasts out, this one is the forecast
-- guard. IN, not a join: join_use_nulls=0 would fill an unmatched join with ''. An undeclared scenario is
-- B5's and assert_scenario_rows_declared's business, not read here.
--
-- Goes in S6 with konsol's refusal, when the latest-estimate read picks the round (FC-2-1) and approved
-- rounds sit side by side (FC-4). Error severity: every reader above would report a doubled forecast.
-- Fixtures: assert_forecast_one_approved_round_until_s6.must_flag.sql (two cycles: 1 result),
-- assert_forecast_one_approved_round_until_s6.one_round.sql (one cycle, and a two-cycle budget: pass).
{{ config(severity='error') }}

select
    scenario_id,
    fiscal_year,
    groupUniqArray(cycle) as cycles
from {{ ref('gold_spread_budget') }}
where scenario_id in (
    select scenario_id
    from {{ source('epm_gold', 'scenario_definitions') }}
    where scenario_type = 'forecast'
)
group by scenario_id, fiscal_year
having uniqExact(cycle) > 1
