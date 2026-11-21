-- gate: expect assert_forecast_accuracy_horizon_hand_table flag 1
-- konsol#348 S6 WC2 review (m1, m2): the horizon hand table can fail. gold_forecast_accuracy seeded
-- straight into its table (test mode) with the eight expected rows of
-- assert_forecast_accuracy_horizon_hand_table.sql PLUS round B's FY2027 P3 row (-33 vs -24, lag 3): beyond
-- B's horizon of 2, and what a model would show that took the longest horizon per scenario (12, round A's)
-- instead of per round (scenario_id, as_of_date). That row is produced and not expected: 1 result (net -1).
-- Budget dimensions at the fixture dims are dim_cost_center and dim_department; the live table may have
-- been built at other dims, so they are added by ALTER first.
ALTER TABLE epm_gold.gold_forecast_accuracy ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_forecast_accuracy ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_forecast_accuracy
  (scenario_id, cycle, as_of_date, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, dim_department, currency, lag, forecast_amount, actual_amount, forecast_error, forecast_abs_error, forecast_error_pct)
VALUES
  ('ZZ_FC_HZN', 'ZZ-HZN-A26', '2026-09-30', 'ZZH1', 2026, 10, 'ZZ4000', '', '', 'USD', 1, -100, -105, 5, 5, 4.761904761904762),
  ('ZZ_FC_HZN', 'ZZ-HZN-A26', '2026-09-30', 'ZZH1', 2026, 11, 'ZZ4000', '', '', 'USD', 2, -110, -110, 0, 0, 0.0),
  ('ZZ_FC_HZN', 'ZZ-HZN-A26', '2026-09-30', 'ZZH1', 2026, 12, 'ZZ4000', '', '', 'USD', 3, -120, -100, -20, 20, -20.0),
  ('ZZ_FC_HZN', 'ZZ-HZN-A27', '2026-09-30', 'ZZH1', 2027, 1, 'ZZ4000', '', '', 'USD', 4, -10, -15, 5, 5, 33.33333333333333),
  ('ZZ_FC_HZN', 'ZZ-HZN-A27', '2026-09-30', 'ZZH1', 2027, 2, 'ZZ4000', '', '', 'USD', 5, -20, -20, 0, 0, 0.0),
  ('ZZ_FC_HZN', 'ZZ-HZN-A27', '2026-09-30', 'ZZH1', 2027, 3, 'ZZ4000', '', '', 'USD', 6, -30, -24, -6, 6, -25.0),
  ('ZZ_FC_HZN', 'ZZ-HZN-B27', '2026-12-31', 'ZZH1', 2027, 1, 'ZZ4000', '', '', 'USD', 1, -12, -15, 3, 3, 20.0),
  ('ZZ_FC_HZN', 'ZZ-HZN-B27', '2026-12-31', 'ZZH1', 2027, 2, 'ZZ4000', '', '', 'USD', 2, -18, -20, 2, 2, 10.0),
  ('ZZ_FC_HZN', 'ZZ-HZN-B27', '2026-12-31', 'ZZH1', 2027, 3, 'ZZ4000', '', '', 'USD', 3, -33, -24, -9, 9, -37.5);
