-- gate: expect assert_forecast_accuracy_hand_table flag 1
-- konsol#348 S6 WC2: the hand table can fail. gold_forecast_accuracy seeded straight into its table
-- (test mode) with the six expected rows of assert_forecast_accuracy_hand_table.sql PLUS R1's P7 row
-- (-70 vs -71, lag 4): P7 is Open, and a model that measured an open period (S6-Q8 a) would show it.
-- That row is produced and not expected: 1 result (net -1).
-- Budget dimensions at the fixture dims are dim_cost_center and dim_department; the live table may have
-- been built at other dims, so they are added by ALTER first.
ALTER TABLE epm_gold.gold_forecast_accuracy ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_forecast_accuracy ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_forecast_accuracy
  (scenario_id, cycle, as_of_date, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, dim_department, currency, lag, forecast_amount, actual_amount, forecast_error, forecast_abs_error, forecast_error_pct)
VALUES
  ('ZZ_FC_ACC', 'ZZ-ACC-R1', '2026-03-31', 'ZZE1', 2026, 4, 'ZZ4000', '', '', 'USD', 1, -42, -45, 3, 3, 6.666666666666667),
  ('ZZ_FC_ACC', 'ZZ-ACC-R1', '2026-03-31', 'ZZE1', 2026, 4, 'ZZ6000', '', '', 'USD', 1, 0, 10, -10, 10, -100),
  ('ZZ_FC_ACC', 'ZZ-ACC-R1', '2026-03-31', 'ZZE1', 2026, 5, 'ZZ4000', '', '', 'USD', 2, -50, -50, 0, 0, 0),
  ('ZZ_FC_ACC', 'ZZ-ACC-R1', '2026-03-31', 'ZZE1', 2026, 5, 'ZZ5000', '', '', 'USD', 2, 20, 0, 20, 20, NULL),
  ('ZZ_FC_ACC', 'ZZ-ACC-R1', '2026-03-31', 'ZZE1', 2026, 6, 'ZZ4000', '', '', 'USD', 3, -60, -55, -5, 5, -9.090909090909092),
  ('ZZ_FC_ACC', 'ZZ-ACC-R2', '2026-05-31', 'ZZE1', 2026, 6, 'ZZ4000', '', '', 'USD', 1, -66, -55, -11, 11, -20),
  ('ZZ_FC_ACC', 'ZZ-ACC-R1', '2026-03-31', 'ZZE1', 2026, 7, 'ZZ4000', '', '', 'USD', 4, -70, -71, 1, 1, 1.408450704225352);
