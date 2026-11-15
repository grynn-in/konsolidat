-- gate: build gold_spread_budget assert_spread_sums_to_annual
-- gate: expect assert_spread_sums_to_annual pass
-- konsol#348 S3 B12 (QB6 a): annual_amount is signed like the actuals, debit positive, so a revenue budget is
-- negative. One annual input of -1200 on revenue account ZZ4000, spread by a flat 12-period profile, gives twelve
-- period amounts of -100 summing to -1200: the test compares the signed values (abs() is on the gap only) and must
-- PASS. A test that took abs() of either side would compare 1200 with -1200 and flag a gap of 2400.
-- epm_raw.budget_entries is read too, empty here, so it is created empty. The live annual table may predate `cycle`
-- (B3w): add it to the scratch clone first.
ALTER TABLE epm_gold.budget_annual_input ADD COLUMN IF NOT EXISTS cycle String;
INSERT INTO epm_gold.budget_annual_input
  (scenario_id, cycle, data_area_id, fiscal_year, main_account, layer, currency, annual_amount, spread_profile_id, submitted_by)
VALUES
  ('ZZ_PLAN_2026', 'ZZ-CY-2026', 'ZZE1', 2026, 'ZZ4000', 'base', 'USD', -1200, 'ZZ_FLAT', 'zz');
INSERT INTO epm_gold.spread_profiles (profile_id, profile_name, fiscal_period, weight) VALUES
  ('ZZ_FLAT', 'ZZ flat', 1, 1), ('ZZ_FLAT', 'ZZ flat', 2, 1), ('ZZ_FLAT', 'ZZ flat', 3, 1), ('ZZ_FLAT', 'ZZ flat', 4, 1),
  ('ZZ_FLAT', 'ZZ flat', 5, 1), ('ZZ_FLAT', 'ZZ flat', 6, 1), ('ZZ_FLAT', 'ZZ flat', 7, 1), ('ZZ_FLAT', 'ZZ flat', 8, 1),
  ('ZZ_FLAT', 'ZZ flat', 9, 1), ('ZZ_FLAT', 'ZZ flat', 10, 1), ('ZZ_FLAT', 'ZZ flat', 11, 1), ('ZZ_FLAT', 'ZZ flat', 12, 1);
