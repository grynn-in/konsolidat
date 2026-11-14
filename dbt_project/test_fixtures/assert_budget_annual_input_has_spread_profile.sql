-- gate: expect assert_budget_annual_input_has_spread_profile pass
-- konsol#525: every annual input names a Spread Profile that exists (profile_id). Both inputs do, so the test
-- must PASS. A second input at another grain shares the profile.
INSERT INTO epm_gold.budget_annual_input
  (scenario_id, data_area_id, fiscal_year, main_account, layer, currency, annual_amount, spread_profile_id, submitted_by)
VALUES
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4000', 'base', 'USD', 1200, 'ZZ_EVEN', 'zz'),
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4100', 'base', 'USD', 600, 'ZZ_EVEN', 'zz');
INSERT INTO epm_gold.spread_profiles (profile_id, profile_name, fiscal_period, weight) VALUES
  ('ZZ_EVEN', 'ZZ even', 1, 1),
  ('ZZ_EVEN', 'ZZ even', 2, 1);
