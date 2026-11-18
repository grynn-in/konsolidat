-- konsol#348 S6-Q1 (b), decided by Deepak Pai, 17 Nov 2026 (#348 comment 6953756459): a forecast
-- (scenario, fiscal year) has at most ONE current round. gold_forecast_current_round is the one
-- selection every forecast reader joins (gold_scenario_trial_balance, gold_forecast_current,
-- gold_forecast_current_at_hierarchy_node, gold_latest_estimate_current); two rows for one pair would
-- make those readers sum two rounds again, which is what the declaration exists to prevent. konsol
-- holds one live Current Forecast per pair (FOR UPDATE on its live index) and the write-through
-- replaces the whole table, so a second row here is sync drift or a hand-written row, and the build
-- must stop rather than double a forecast. Error severity.
-- Fixtures: assert_forecast_current_round_unique.must_flag.sql (two declarations for one pair: 1 result),
-- gold_forecast_current_round.two_rounds.sql (two approved rounds, one declared: pass).
{{ config(severity='error') }}

select
    scenario_id,
    fiscal_year,
    groupUniqArray(cycle) as cycles,
    count() as rows_for_pair
from {{ ref('gold_forecast_current_round') }}
group by scenario_id, fiscal_year
having count() > 1
