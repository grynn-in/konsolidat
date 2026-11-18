-- gate: expect assert_forecast_accuracy_grain_unique flag 1
-- konsol#348 S6 WC2: one row per key. gold_forecast_accuracy seeded straight into its table (test mode)
-- with R1's P4 ZZ4000 key on two rows: the forecast side (-42, actual 0) and the actual side (0, -45),
-- the two halves a model that did not sum them would leave. One key, two rows: 1 result. R1's P5 row is
-- alone on its key: not named.
-- Budget dimensions at the fixture dims are dim_cost_center and dim_department; the live table may have
-- been built at other dims, so they are added by ALTER first.
ALTER TABLE epm_gold.gold_forecast_accuracy ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_forecast_accuracy ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_forecast_accuracy
  (scenario_id, cycle, as_of_date, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, dim_department, currency, lag, forecast_amount, actual_amount, forecast_error, forecast_abs_error, forecast_error_pct)
VALUES
  ('ZZ_FC_ACC', 'ZZ-ACC-R1', '2026-03-31', 'ZZE1', 2026, 4, 'ZZ4000', '', '', 'USD', 1, -42, 0, -42, 42, NULL),
  ('ZZ_FC_ACC', 'ZZ-ACC-R1', '2026-03-31', 'ZZE1', 2026, 4, 'ZZ4000', '', '', 'USD', 1, 0, -45, 45, 45, 100),
  ('ZZ_FC_ACC', 'ZZ-ACC-R1', '2026-03-31', 'ZZE1', 2026, 5, 'ZZ4000', '', '', 'USD', 2, -50, -50, 0, 0, 0);
