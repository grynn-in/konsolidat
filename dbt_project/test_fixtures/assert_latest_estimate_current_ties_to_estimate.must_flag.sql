-- gate: expect assert_latest_estimate_current_ties_to_estimate flag 1
-- konsol#348 S6 pair A review M2: the Excel latest-estimate read summing rounds, seeded straight into the
-- view's scratch table (test mode clones a view as a table): gold_latest_estimate_current holds BOTH
-- approved rounds of ZZ_FC_LE FY2026 (R1 -70, R2 -162) while the Current Forecast declares R2 and
-- gold_latest_estimate holds both rounds. The R2 key ties (3 rows, -162 each side); the R1 key is in the
-- view and is not the declared round: 1 result.
INSERT INTO epm_gold.gold_forecast_current_round
  (scenario_id, fiscal_year, cycle, as_of_date, horizon_periods, rate_set)
VALUES
  ('ZZ_FC_LE', 2026, 'ZZ-LE-R2', '2026-06-30', 6, 'ZZRS');
INSERT INTO epm_gold.gold_latest_estimate
  (scenario_id, cycle, as_of_date, data_area_id, fiscal_year, fiscal_period, main_account, currency,
   period_amount, source)
VALUES
  ('ZZ_FC_LE', 'ZZ-LE-R1', '2026-03-31', 'ZZE1', 2026, 3, 'ZZ4000', 'USD', -30, 'actual'),
  ('ZZ_FC_LE', 'ZZ-LE-R1', '2026-03-31', 'ZZE1', 2026, 4, 'ZZ4000', 'USD', -40, 'forecast'),
  ('ZZ_FC_LE', 'ZZ-LE-R2', '2026-06-30', 'ZZE1', 2026, 3, 'ZZ4000', 'USD', -30, 'actual'),
  ('ZZ_FC_LE', 'ZZ-LE-R2', '2026-06-30', 'ZZE1', 2026, 6, 'ZZ4000', 'USD', -60, 'actual'),
  ('ZZ_FC_LE', 'ZZ-LE-R2', '2026-06-30', 'ZZE1', 2026, 7, 'ZZ4000', 'USD', -72, 'forecast');
INSERT INTO epm_gold.gold_latest_estimate_current
  (scenario_id, cycle, as_of_date, data_area_id, fiscal_year, fiscal_period, main_account, currency,
   period_amount, source)
VALUES
  ('ZZ_FC_LE', 'ZZ-LE-R1', '2026-03-31', 'ZZE1', 2026, 3, 'ZZ4000', 'USD', -30, 'actual'),
  ('ZZ_FC_LE', 'ZZ-LE-R1', '2026-03-31', 'ZZE1', 2026, 4, 'ZZ4000', 'USD', -40, 'forecast'),
  ('ZZ_FC_LE', 'ZZ-LE-R2', '2026-06-30', 'ZZE1', 2026, 3, 'ZZ4000', 'USD', -30, 'actual'),
  ('ZZ_FC_LE', 'ZZ-LE-R2', '2026-06-30', 'ZZE1', 2026, 6, 'ZZ4000', 'USD', -60, 'actual'),
  ('ZZ_FC_LE', 'ZZ-LE-R2', '2026-06-30', 'ZZE1', 2026, 7, 'ZZ4000', 'USD', -72, 'forecast');
