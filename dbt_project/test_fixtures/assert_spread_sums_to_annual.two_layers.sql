-- gate: build gold_spread_budget assert_spread_sums_to_annual
-- gate: expect assert_spread_sums_to_annual pass
-- Two manual layers (base, challenge) of one account, each totalling 1200, are two legitimate grains
-- (gold_spread_budget gives each layer its own annual_amount): the test must PASS, not read them as 2400 vs 1200.
-- epm_gold.budget_annual_input and epm_gold.spread_profiles are read too, empty here, so they are named to exist (empty).
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis, dim_cost_center, dim_department)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 600, 0, 'USD', 'Period movement', '', ''),
  ('ZZ-BE-2', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 2, 'ZZ4000', 600, 0, 'USD', 'Period movement', '', ''),
  ('ZZ-BE-3', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'challenge', 'ZZE1', 2026, 1, 'ZZ4000', 600, 0, 'USD', 'Period movement', '', ''),
  ('ZZ-BE-4', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'challenge', 'ZZE1', 2026, 2, 'ZZ4000', 600, 0, 'USD', 'Period movement', '', '');
