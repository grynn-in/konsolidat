-- gate: build gold_spread_budget assert_budget_fact_grain_unique assert_spread_sums_to_annual
-- gate: expect assert_budget_fact_grain_unique pass
-- gate: expect assert_spread_sums_to_annual pass
-- konsol#348 S2 (R8, Q16-c): the annual branch of gold_spread_budget carries each Annual Input's own
-- layer (R6 added the column). One account has a 'base' annual input of 1200 and a 'challenge' one of
-- 600: two layers, two grains, each spread over 12 periods and summing to its own amount.
-- Red while the branch writes the literal 'base': both inputs land on the base grain, every period holds
-- two rows (grain test flags 12) and the base grain spreads 1800 against 1200 (sums test flags 1).
-- epm_raw.budget_entries is read too, empty here, so it is created empty.
INSERT INTO epm_gold.budget_annual_input
  (scenario_id, data_area_id, fiscal_year, main_account, layer, currency, annual_amount, spread_profile_id, submitted_by)
VALUES
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4000', 'base', 'USD', 1200, 'ZZ_FLAT', 'zz'),
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4000', 'challenge', 'USD', 600, 'ZZ_FLAT', 'zz');
INSERT INTO epm_gold.spread_profiles (profile_id, profile_name, fiscal_period, weight) VALUES
  ('ZZ_FLAT', 'ZZ flat', 1, 1), ('ZZ_FLAT', 'ZZ flat', 2, 1), ('ZZ_FLAT', 'ZZ flat', 3, 1), ('ZZ_FLAT', 'ZZ flat', 4, 1),
  ('ZZ_FLAT', 'ZZ flat', 5, 1), ('ZZ_FLAT', 'ZZ flat', 6, 1), ('ZZ_FLAT', 'ZZ flat', 7, 1), ('ZZ_FLAT', 'ZZ flat', 8, 1),
  ('ZZ_FLAT', 'ZZ flat', 9, 1), ('ZZ_FLAT', 'ZZ flat', 10, 1), ('ZZ_FLAT', 'ZZ flat', 11, 1), ('ZZ_FLAT', 'ZZ flat', 12, 1);
