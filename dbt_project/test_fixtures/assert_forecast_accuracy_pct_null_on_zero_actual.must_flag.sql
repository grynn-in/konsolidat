-- gate: expect assert_forecast_accuracy_pct_null_on_zero_actual flag 2
-- konsol#348 S6 WC2: the error percentage is NULL exactly on a zero actual. gold_forecast_accuracy seeded
-- straight into its table (test mode): R1 P5 ZZ5000 (actual 0) with a percentage of 0, the "perfect
-- forecast" a coalesce would invent; R1 P4 ZZ4000 (actual -45) with a NULL percentage. 2 results. R1 P6
-- (-5 / |-55| x 100 = -9.0909...) is right: not named.
-- Budget dimensions at the fixture dims are dim_cost_center and dim_department; the live table may have
-- been built at other dims, so they are added by ALTER first.
ALTER TABLE epm_gold.gold_forecast_accuracy ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_forecast_accuracy ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_forecast_accuracy
  (scenario_id, cycle, as_of_date, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, dim_department, currency, lag, forecast_amount, actual_amount, forecast_error, forecast_abs_error, forecast_error_pct)
VALUES
  ('ZZ_FC_ACC', 'ZZ-ACC-R1', '2026-03-31', 'ZZE1', 2026, 5, 'ZZ5000', '', '', 'USD', 2, 20, 0, 20, 20, 0),
  ('ZZ_FC_ACC', 'ZZ-ACC-R1', '2026-03-31', 'ZZE1', 2026, 4, 'ZZ4000', '', '', 'USD', 1, -42, -45, 3, 3, NULL),
  ('ZZ_FC_ACC', 'ZZ-ACC-R1', '2026-03-31', 'ZZE1', 2026, 6, 'ZZ4000', '', '', 'USD', 3, -60, -55, -5, 5, -9.090909090909092);
