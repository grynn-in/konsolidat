-- gate: expect assert_budget_annual_input_has_spread_profile flag 3
-- konsol#525: gold_spread_budget inner-joins spread_profiles on profile_id, so an annual input whose
-- spread_profile_id matches none is dropped from the budget fact without a word. Three inputs are flagged,
-- one row each: the Spread Profile row name (ZZ_EVEN-P1, the case found live), a profile never created, and
-- a different-case key (the join is an exact match). The input on ZZ_EVEN is not flagged, and a profile
-- with two periods does not multiply a flagged input.
INSERT INTO epm_gold.budget_annual_input
  (scenario_id, data_area_id, fiscal_year, main_account, layer, currency, annual_amount, spread_profile_id, submitted_by)
VALUES
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4000', 'base', 'USD', 1200, 'ZZ_EVEN', 'zz'),
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4100', 'base', 'USD', 600, 'SP-ZZ_EVEN-P1', 'zz'),
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4200', 'base', 'USD', 600, 'ZZ_NONE', 'zz'),
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4300', 'base', 'USD', 600, 'zz_even', 'zz');
INSERT INTO epm_gold.spread_profiles (profile_id, profile_name, fiscal_period, weight) VALUES
  ('ZZ_EVEN', 'ZZ even', 1, 1),
  ('ZZ_EVEN', 'ZZ even', 2, 1);
