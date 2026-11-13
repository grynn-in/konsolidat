-- gate: build gold_spread_budget assert_spread_sums_to_annual
-- gate: expect assert_spread_sums_to_annual flag 1
-- Two annual inputs for one grain with different amounts (1200 and 600, ZZ_PLAN_2026 / ZZE1 / 2026 / ZZ4000) are
-- both spread: 1800 against an annual_amount of 1200 at most. The test must FLAG 1 for the grain.
INSERT INTO epm_gold.budget_annual_input
  (scenario_id, data_area_id, fiscal_year, main_account, annual_amount, spread_profile_id, submitted_by)
VALUES
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4000', 1200, 'ZZ_FLAT', 'zz'),
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4000', 600, 'ZZ_FLAT', 'zz');
INSERT INTO epm_gold.spread_profiles (profile_id, profile_name, fiscal_period, weight) VALUES
  ('ZZ_FLAT', 'ZZ flat', 1, 1), ('ZZ_FLAT', 'ZZ flat', 2, 1), ('ZZ_FLAT', 'ZZ flat', 3, 1), ('ZZ_FLAT', 'ZZ flat', 4, 1),
  ('ZZ_FLAT', 'ZZ flat', 5, 1), ('ZZ_FLAT', 'ZZ flat', 6, 1), ('ZZ_FLAT', 'ZZ flat', 7, 1), ('ZZ_FLAT', 'ZZ flat', 8, 1),
  ('ZZ_FLAT', 'ZZ flat', 9, 1), ('ZZ_FLAT', 'ZZ flat', 10, 1), ('ZZ_FLAT', 'ZZ flat', 11, 1), ('ZZ_FLAT', 'ZZ flat', 12, 1);
