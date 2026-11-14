-- gate: build gold_spread_budget assert_spread_sums_to_annual
-- gate: expect assert_spread_sums_to_annual pass
-- Two manual layers (base, challenge) of one account, each totalling 1200, are two legitimate grains
-- (gold_spread_budget gives each layer its own annual_amount): the test must PASS, not read them as 2400 vs 1200.
-- epm_gold.budget_annual_input and epm_gold.spread_profiles are read too, empty here, so they are named to exist (empty).
INSERT INTO epm_gold.budget_monthly_input
  (scenario_id, data_area_id, fiscal_year, main_account, fiscal_period, amount, layer)
VALUES
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4000', 1, 600, 'base'),
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4000', 2, 600, 'base'),
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4000', 1, 600, 'challenge'),
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4000', 2, 600, 'challenge');
