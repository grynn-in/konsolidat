-- gate: build gold_spread_budget assert_spread_sums_to_annual
-- gate: expect assert_spread_sums_to_annual flag 1
-- The same annual input (1200, ZZ_PLAN_2026 / ZZE1 / 2026 / ZZ4000) entered twice is spread twice: the
-- 12 period amounts sum to 2400 against annual_amount 1200, one group with a gap of 1200, so the test must FLAG 1.
INSERT INTO epm_gold.budget_annual_input
  (scenario_id, data_area_id, fiscal_year, main_account, layer, currency, annual_amount, spread_profile_id, submitted_by)
VALUES
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4000', 'base', 'USD', 1200, 'ZZ_FLAT', 'zz'),
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4000', 'base', 'USD', 1200, 'ZZ_FLAT', 'zz');
INSERT INTO epm_gold.spread_profiles (profile_id, profile_name, fiscal_period, weight) VALUES
  ('ZZ_FLAT', 'ZZ flat', 1, 1), ('ZZ_FLAT', 'ZZ flat', 2, 1), ('ZZ_FLAT', 'ZZ flat', 3, 1), ('ZZ_FLAT', 'ZZ flat', 4, 1),
  ('ZZ_FLAT', 'ZZ flat', 5, 1), ('ZZ_FLAT', 'ZZ flat', 6, 1), ('ZZ_FLAT', 'ZZ flat', 7, 1), ('ZZ_FLAT', 'ZZ flat', 8, 1),
  ('ZZ_FLAT', 'ZZ flat', 9, 1), ('ZZ_FLAT', 'ZZ flat', 10, 1), ('ZZ_FLAT', 'ZZ flat', 11, 1), ('ZZ_FLAT', 'ZZ flat', 12, 1);
