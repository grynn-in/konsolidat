-- gate: expect assert_latest_estimate_horizon_hand_table flag 4
-- konsolidat#376: the latest-estimate horizon hand table can fail. gold_latest_estimate seeded straight
-- into its table (test mode) with what a model that cuts each Cycle at its OWN horizon produces on the
-- horizon fixture: the ten expected rows of assert_latest_estimate_horizon_hand_table.sql WITHOUT round
-- A's FY2027 forecast P1-P4 (lags 4-7, beyond the FY2027 Cycle's own 3, inside the round's 12). Those
-- four rows are expected and missing: 4 results (net +1 each).
-- Budget dimensions at the fixture dims are dim_cost_center and dim_department; the live table may have
-- been built at other dims, so they are added by ALTER first.
ALTER TABLE epm_gold.gold_latest_estimate ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_latest_estimate ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_latest_estimate
  (scenario_id, cycle, as_of_date, data_area_id, fiscal_year, fiscal_period, main_account,
   dim_cost_center, dim_department, currency, period_amount, source)
VALUES
  ('ZZ_FC_HZN', 'ZZ-HZN-A26', '2026-09-30', 'ZZH1', 2026, 9, 'ZZ4000', '', '', 'USD', -95, 'actual'),
  ('ZZ_FC_HZN', 'ZZ-HZN-A26', '2026-09-30', 'ZZH1', 2026, 10, 'ZZ4000', '', '', 'USD', -100, 'forecast'),
  ('ZZ_FC_HZN', 'ZZ-HZN-A26', '2026-09-30', 'ZZH1', 2026, 11, 'ZZ4000', '', '', 'USD', -110, 'forecast'),
  ('ZZ_FC_HZN', 'ZZ-HZN-A26', '2026-09-30', 'ZZH1', 2026, 12, 'ZZ4000', '', '', 'USD', -120, 'forecast'),
  ('ZZ_FC_HZN', 'ZZ-HZN-B27', '2026-12-31', 'ZZH1', 2027, 1, 'ZZ4000', '', '', 'USD', -12, 'forecast'),
  ('ZZ_FC_HZN', 'ZZ-HZN-B27', '2026-12-31', 'ZZH1', 2027, 2, 'ZZ4000', '', '', 'USD', -18, 'forecast');
