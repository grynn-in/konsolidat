-- gate: expect assert_variance_covers_budget_scenarios flag 1
-- Same rows as the PASS fixture, but gold_variance_analysis carries -900 for the actual grain (-1000): one
-- actual_amount row, in that model only.
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ACTUAL', 'Actual', 'actual', 1),
  ('ZZ_B26', 'ZZ budget 2026', 'budget', 1);
INSERT INTO epm_gold.gold_period_hierarchy
  (fiscal_period, period_label, fiscal_quarter, fiscal_half)
VALUES (1, 'P01', 'Q1', 'H1');
INSERT INTO epm_gold.gold_scenario_trial_balance
  (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, amount)
VALUES
  ('ACTUAL', 'ZZE1', 2026, 1, 'ZZ4000', -1000),
  ('ZZ_B26', 'ZZE1', 2026, 1, 'ZZ4000', -1200);
INSERT INTO epm_gold.gold_variance_analysis
  (budget_scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, actual_amount)
VALUES ('ZZ_B26', 'ZZE1', 2026, 1, 'ZZ4000', -900);
INSERT INTO epm_gold.gold_variance_quarterly
  (budget_scenario_id, data_area_id, fiscal_year, fiscal_quarter, main_account, actual_amount)
VALUES ('ZZ_B26', 'ZZE1', 2026, 'Q1', 'ZZ4000', -1000);
INSERT INTO epm_gold.gold_variance_ytd
  (budget_scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, ytd_actual)
VALUES ('ZZ_B26', 'ZZE1', 2026, 1, 'ZZ4000', -1000);
