-- gate: build gold_forecast_current_round gold_forecast_current_at_hierarchy_node assert_forecast_current_at_node_ties_to_rollup
-- gate: expect gold_forecast_current_at_hierarchy_node built
-- gate: expect assert_forecast_current_at_node_ties_to_rollup pass
-- konsol#348 S6 pair A review M2 (S6-Q1 b): the Excel hierarchy forecast read's view holds the declared
-- round alone. Forecast scenario ZZ_FC_2026, FY2026 P1, ZZ4000, entity ZZE1 (USD), hierarchy ZZ_H with
-- leaf ZZ_L under group ZZ_G: round ZZ-FC-R1 credits 100 and round ZZ-FC-R2 credits 110, both approved
-- and both in gold_budget_at_hierarchy_node (seeded; the rollup groups by cycle), one row per node and
-- round; the Current Forecast declares R2. gold_forecast_current_at_hierarchy_node, built over it, must
-- hold exactly R2's two node rows (-220) and no R1 row: the ties test passes. Budget scenario
-- ZZ_PLAN_2026 (one Cycle) is in the rollup and not in the view.
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ZZ_FC_2026', 'ZZ forecast', 'forecast', 1),
  ('ZZ_PLAN_2026', 'ZZ plan', 'budget', 1);
INSERT INTO epm_staging.budget_cycles
  (name, scenario_id, fiscal_year, rate_set, as_of_date, horizon_periods)
VALUES
  ('ZZ-FC-R1', 'ZZ_FC_2026', 2026, 'ZZRS', '2026-03-31', 9),
  ('ZZ-FC-R2', 'ZZ_FC_2026', 2026, 'ZZRS', '2026-06-30', 6),
  ('ZZ-CY-A', 'ZZ_PLAN_2026', 2026, 'ZZRS', DEFAULT, 0);
INSERT INTO epm_staging.current_forecasts
  (scenario_id, fiscal_year, cycle)
VALUES
  ('ZZ_FC_2026', 2026, 'ZZ-FC-R2');
INSERT INTO epm_gold.gold_budget_at_hierarchy_node
  (hierarchy_name, hierarchy_dimension, hierarchy_member_code, hierarchy_member_label, hierarchy_level,
   hierarchy_is_group, scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, layer, cycle,
   currency, period_amount, annual_amount)
VALUES
  ('ZZ_H', 'dim_cost_center', 'ZZ_L', 'ZZ leaf', 2, 0, 'ZZ_FC_2026', 'ZZE1', 2026, 1, 'ZZ4000', 'base', 'ZZ-FC-R1', 'USD', -100, -100),
  ('ZZ_H', 'dim_cost_center', 'ZZ_G', 'ZZ group', 1, 1, 'ZZ_FC_2026', 'ZZE1', 2026, 1, 'ZZ4000', 'base', 'ZZ-FC-R1', 'USD', -100, -100),
  ('ZZ_H', 'dim_cost_center', 'ZZ_L', 'ZZ leaf', 2, 0, 'ZZ_FC_2026', 'ZZE1', 2026, 1, 'ZZ4000', 'base', 'ZZ-FC-R2', 'USD', -110, -110),
  ('ZZ_H', 'dim_cost_center', 'ZZ_G', 'ZZ group', 1, 1, 'ZZ_FC_2026', 'ZZE1', 2026, 1, 'ZZ4000', 'base', 'ZZ-FC-R2', 'USD', -110, -110),
  ('ZZ_H', 'dim_cost_center', 'ZZ_L', 'ZZ leaf', 2, 0, 'ZZ_PLAN_2026', 'ZZE1', 2026, 1, 'ZZ4000', 'base', 'ZZ-CY-A', 'USD', -100, -100);
