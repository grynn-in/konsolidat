-- gate: expect assert_forecast_accuracy_group_hand_table flag 2
-- konsol#348 S6 WC3: the hand table can fail. gold_forecast_accuracy_group seeded straight into its table
-- (test mode) with the five expected rows of assert_forecast_accuracy_group_hand_table.sql, except that
-- ZZE2's actual is its local amount (-100, EUR) instead of the group's (-120, USD at the actuals' 1.2):
-- the error loses the FX movement (-10, not 10). The expected ZZE2 row is missing (net +1) and the
-- seeded one is not expected (net -1): 2 results.
INSERT INTO epm_gold.gold_forecast_accuracy_group
  (consolidation_group, scenario_id, cycle, as_of_date, data_area_id, fiscal_year, fiscal_period, main_account,
   reporting_currency, lag, forecast_amount, actual_amount, forecast_error, forecast_abs_error, forecast_error_pct)
VALUES
  ('ZZG', 'ZZ_FC_ACG', 'ZZ-ACG-R1', '2026-03-31', 'ZZE1', 2026, 4, 'ZZ4000', 'USD', 1, -50, -40, -10, 10, -25),
  ('ZZG', 'ZZ_FC_ACG', 'ZZ-ACG-R1', '2026-03-31', 'ZZE1', 2026, 4, 'ZZ5000', 'USD', 1, 20, 0, 20, 20, NULL),
  ('ZZG', 'ZZ_FC_ACG', 'ZZ-ACG-R1', '2026-03-31', 'ZZE1', 2026, 4, 'ZZ6000', 'USD', 1, 0, 8, -8, 8, -100),
  ('ZZG', 'ZZ_FC_ACG', 'ZZ-ACG-R1', '2026-03-31', 'ZZE2', 2026, 4, 'ZZ4000', 'USD', 1, -110, -100, -10, 10, -10),
  ('ZZG2', 'ZZ_FC_ACG', 'ZZ-ACG-R1', '2026-03-31', 'ZZE1', 2026, 4, 'ZZ4000', 'USD', 1, -25, -20, -5, 5, -25);
