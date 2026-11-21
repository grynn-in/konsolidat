-- gate: expect assert_latest_estimate_hand_table flag 1
-- konsol#348 S6 WA7: the hand table can fail. gold_latest_estimate seeded straight into its table
-- (test mode) with the six expected rows of assert_latest_estimate_hand_table.sql PLUS R2's P7 actual
-- (-70): the period after the as-of read from the actual side, the off-by-one the lag rule prevents.
-- That row is produced and not expected: 1 result (net -1).
-- Budget dimensions at the fixture dims are dim_cost_center and dim_department; the live table may have
-- been built at other dims, so they are added by ALTER first.
ALTER TABLE epm_gold.gold_latest_estimate ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_latest_estimate ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_latest_estimate
  (scenario_id, cycle, as_of_date, data_area_id, fiscal_year, fiscal_period, main_account,
   dim_cost_center, dim_department, currency, period_amount, source)
VALUES
  ('ZZ_FC_LE', 'ZZ-LE-R1', '2026-03-31', 'ZZE1', 2026, 3, 'ZZ4000', '', '', 'USD', -30, 'actual'),
  ('ZZ_FC_LE', 'ZZ-LE-R1', '2026-03-31', 'ZZE1', 2026, 4, 'ZZ4000', '', '', 'USD', -40, 'forecast'),
  ('ZZ_FC_LE', 'ZZ-LE-R2', '2026-06-30', 'ZZE1', 2026, 3, 'ZZ4000', '', '', 'USD', -30, 'actual'),
  ('ZZ_FC_LE', 'ZZ-LE-R2', '2026-06-30', 'ZZE1', 2026, 6, 'ZZ4000', '', '', 'USD', -60, 'actual'),
  ('ZZ_FC_LE', 'ZZ-LE-R2', '2026-06-30', 'ZZE1', 2026, 7, 'ZZ4000', '', '', 'USD', -72, 'forecast'),
  ('ZZ_FC_LE', 'ZZ-LE-R2', '2026-06-30', 'ZZE1', 2026, 12, 'ZZ4000', '', '', 'USD', -120, 'forecast'),
  ('ZZ_FC_LE', 'ZZ-LE-R2', '2026-06-30', 'ZZE1', 2026, 7, 'ZZ4000', '', '', 'USD', -70, 'actual');
