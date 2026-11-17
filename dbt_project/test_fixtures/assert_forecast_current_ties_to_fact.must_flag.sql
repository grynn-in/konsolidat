-- gate: expect assert_forecast_current_ties_to_fact flag 1
-- konsol#348 S6-Q1 (b): the pre-S6 shape of the Excel forecast read, seeded straight into the view's
-- scratch table (test mode clones a view as a table): gold_forecast_current holds BOTH approved rounds of
-- ZZ_FC_2026 FY2026 (R1 -100 and R2 -110) while the Current Forecast declares R2 and the fact holds one
-- row per round. The R2 key ties; the R1 key is in the view and not in the declared round: 1 result.
-- Budget dimensions at the fixture dims are dim_cost_center and dim_department; the live tables may have
-- been built at other dims, so they are added by ALTER first.
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
  ('ZZ_FC_2026', 'ZZ-FC-R2', 'ZZE1', 2026, 1, 'ZZ4000', '', '', 'base', 'USD', -110, 'manual', 'Manual (as-entered)', 1, -110, '');
ALTER TABLE epm_gold.gold_forecast_current ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_forecast_current ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_forecast_current
  (scenario_id, cycle, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, dim_department,
   layer, currency, annual_amount, spread_profile_id, profile_name, period_weight, period_amount, submitted_by)
VALUES
  ('ZZ_FC_2026', 'ZZ-FC-R1', 'ZZE1', 2026, 1, 'ZZ4000', '', '', 'base', 'USD', -100, 'manual', 'Manual (as-entered)', 1, -100, ''),
  ('ZZ_FC_2026', 'ZZ-FC-R2', 'ZZE1', 2026, 1, 'ZZ4000', '', '', 'base', 'USD', -110, 'manual', 'Manual (as-entered)', 1, -110, '');
