-- gate: expect assert_scenario_tb_forecast_is_current_round flag 1
-- konsol#348 S6-Q1 (b): the shape of the pre-WA4 scenario TB, seeded straight into the model's table
-- (test mode): the two approved rounds of ZZ_FC_2026 FY2026 P1 ZZ4000 (R1 100, R2 110) SUMMED to -210,
-- while the Current Forecast declares R2 and the fact (gold_spread_budget, seeded as the model builds
-- it) holds -100 under R1 and -110 under R2. Expected -110 against -210: 1 result. The budget scenario's
-- row (ZZ_PLAN_2026, -100) is not a forecast and is not named.
-- Budget dimensions at the fixture dims are dim_cost_center and dim_department; the live tables may
-- have been built at other dims, so they are added by ALTER first.
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ZZ_FC_2026', 'ZZ forecast', 'forecast', 1),
  ('ZZ_PLAN_2026', 'ZZ plan', 'budget', 1);
INSERT INTO epm_gold.gold_forecast_current_round
  (scenario_id, fiscal_year, cycle, as_of_date, horizon_periods, rate_set)
VALUES
  ('ZZ_FC_2026', 2026, 'ZZ-FC-R2', '2026-06-30', 6, 'ZZRS');
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_spread_budget
  (scenario_id, cycle, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, dim_department,
   layer, currency, annual_amount, spread_profile_id, profile_name, period_weight, period_amount, submitted_by)
VALUES
  ('ZZ_FC_2026', 'ZZ-FC-R1', 'ZZE1', 2026, 1, 'ZZ4000', '', '', 'base', 'USD', -100, 'manual', 'Manual (as-entered)', 1, -100, ''),
  ('ZZ_FC_2026', 'ZZ-FC-R2', 'ZZE1', 2026, 1, 'ZZ4000', '', '', 'base', 'USD', -110, 'manual', 'Manual (as-entered)', 1, -110, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-A', 'ZZE1', 2026, 1, 'ZZ4000', '', '', 'base', 'USD', -100, 'manual', 'Manual (as-entered)', 1, -100, '');
ALTER TABLE epm_gold.gold_scenario_trial_balance ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_scenario_trial_balance ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_scenario_trial_balance
  (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name,
   dim_cost_center, dim_department, currency, amount, data_source)
VALUES
  ('ZZ_FC_2026', 'ZZE1', 2026, 1, 'ZZ4000', '', '', '', '', 'USD', -210, 'budget'),
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 1, 'ZZ4000', '', '', '', '', 'USD', -100, 'budget');
