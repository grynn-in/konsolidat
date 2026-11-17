-- gate: expect assert_forecast_current_at_node_ties_to_rollup flag 1
-- konsol#348 S6 pair A review M2: the pre-S6 shape of the Excel hierarchy forecast read, seeded straight
-- into the view's scratch table (test mode clones a view as a table): gold_forecast_current_at_hierarchy_node
-- holds BOTH approved rounds of ZZ_FC_2026 FY2026 (R1 -100 and R2 -110 at leaf ZZ_L) while the Current
-- Forecast declares R2 and the rollup holds one row per round. The R2 key ties; the R1 key is in the
-- view and is not the declared round: 1 result.
INSERT INTO epm_gold.gold_forecast_current_round
  (scenario_id, fiscal_year, cycle, as_of_date, horizon_periods, rate_set)
VALUES
  ('ZZ_FC_2026', 2026, 'ZZ-FC-R2', '2026-06-30', 6, 'ZZRS');
INSERT INTO epm_gold.gold_budget_at_hierarchy_node
  (hierarchy_name, hierarchy_dimension, hierarchy_member_code, hierarchy_member_label, hierarchy_level,
   hierarchy_is_group, scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, layer, cycle,
   currency, period_amount, annual_amount)
VALUES
  ('ZZ_H', 'dim_cost_center', 'ZZ_L', 'ZZ leaf', 2, 0, 'ZZ_FC_2026', 'ZZE1', 2026, 1, 'ZZ4000', 'base', 'ZZ-FC-R1', 'USD', -100, -100),
  ('ZZ_H', 'dim_cost_center', 'ZZ_L', 'ZZ leaf', 2, 0, 'ZZ_FC_2026', 'ZZE1', 2026, 1, 'ZZ4000', 'base', 'ZZ-FC-R2', 'USD', -110, -110);
INSERT INTO epm_gold.gold_forecast_current_at_hierarchy_node
  (hierarchy_name, hierarchy_dimension, hierarchy_member_code, hierarchy_member_label, hierarchy_level,
   hierarchy_is_group, scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, layer, cycle,
   currency, period_amount, annual_amount)
VALUES
  ('ZZ_H', 'dim_cost_center', 'ZZ_L', 'ZZ leaf', 2, 0, 'ZZ_FC_2026', 'ZZE1', 2026, 1, 'ZZ4000', 'base', 'ZZ-FC-R1', 'USD', -100, -100),
  ('ZZ_H', 'dim_cost_center', 'ZZ_L', 'ZZ leaf', 2, 0, 'ZZ_FC_2026', 'ZZE1', 2026, 1, 'ZZ4000', 'base', 'ZZ-FC-R2', 'USD', -110, -110);
