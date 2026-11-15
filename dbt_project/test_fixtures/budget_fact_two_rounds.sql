-- gate: build gold_spread_budget assert_budget_fact_per_cycle assert_budget_fact_grain_unique assert_spread_sums_to_annual
-- gate: expect assert_budget_fact_per_cycle pass
-- gate: expect assert_budget_fact_grain_unique pass
-- gate: expect assert_spread_sums_to_annual pass
-- konsol#348 S3 B4 (QB2 a, Q23 a): two approved forecast rounds in one year stay apart in the budget fact.
-- Scenario ZZ_FC_2026 is declared scenario_type 'forecast'. Round 1 (cycle ZZ-FC-R1) and round 2 (cycle
-- ZZ-FC-R2) both budget FY2026, entity ZZE1, base layer:
--   * manual lines on ZZ4000: R1 P1 -100, P2 -120 | R2 P1 -110, P2 -130 (Period movement, USD);
--   * annual inputs on ZZ7000, flat 12-period profile: R1 1200 | R2 1800 (USD).
-- The fact must hold one manual row per (cycle, period, account) with the round's own amount, and one
-- annual-spread row per (cycle, period) summing to the round's own annual amount. Never -210 at P1, never
-- 3000 for ZZ7000.
--
-- Red on the S2 model: gold_spread_budget has no `cycle` column, so assert_budget_fact_per_cycle errors
-- (missing column), and the grain and sums tests, which grouped without the cycle, would pass on a fact
-- that summed the rounds. Green once the fact carries the cycle and every test groups by it.
--
-- gold_spread_budget also reads epm_gold.spread_profiles (seeded) and epm_gold.budget_annual_input; the
-- live annual table may predate `cycle` (B3w): add it to the scratch clone first.
ALTER TABLE epm_gold.budget_annual_input ADD COLUMN IF NOT EXISTS cycle String;
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ZZ_FC_2026', 'ZZ forecast 2026', 'forecast', 1);
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis, dim_cost_center, dim_department)
VALUES
  ('ZZ-BE-R1', 'ZZ-FC-R1', 'ZZ_FC_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 100, 'USD', 'Period movement', '', ''),
  ('ZZ-BE-R1', 'ZZ-FC-R1', 'ZZ_FC_2026', 'base', 'ZZE1', 2026, 2, 'ZZ4000', 0, 120, 'USD', 'Period movement', '', ''),
  ('ZZ-BE-R2', 'ZZ-FC-R2', 'ZZ_FC_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 110, 'USD', 'Period movement', '', ''),
  ('ZZ-BE-R2', 'ZZ-FC-R2', 'ZZ_FC_2026', 'base', 'ZZE1', 2026, 2, 'ZZ4000', 0, 130, 'USD', 'Period movement', '', '');
INSERT INTO epm_gold.budget_annual_input
  (scenario_id, data_area_id, fiscal_year, cycle, main_account, layer, currency, annual_amount, spread_profile_id, submitted_by)
VALUES
  ('ZZ_FC_2026', 'ZZE1', 2026, 'ZZ-FC-R1', 'ZZ7000', 'base', 'USD', 1200, 'ZZ_FLAT', 'zz'),
  ('ZZ_FC_2026', 'ZZE1', 2026, 'ZZ-FC-R2', 'ZZ7000', 'base', 'USD', 1800, 'ZZ_FLAT', 'zz');
INSERT INTO epm_gold.spread_profiles (profile_id, profile_name, fiscal_period, weight) VALUES
  ('ZZ_FLAT', 'ZZ flat', 1, 1), ('ZZ_FLAT', 'ZZ flat', 2, 1), ('ZZ_FLAT', 'ZZ flat', 3, 1), ('ZZ_FLAT', 'ZZ flat', 4, 1),
  ('ZZ_FLAT', 'ZZ flat', 5, 1), ('ZZ_FLAT', 'ZZ flat', 6, 1), ('ZZ_FLAT', 'ZZ flat', 7, 1), ('ZZ_FLAT', 'ZZ flat', 8, 1),
  ('ZZ_FLAT', 'ZZ flat', 9, 1), ('ZZ_FLAT', 'ZZ flat', 10, 1), ('ZZ_FLAT', 'ZZ flat', 11, 1), ('ZZ_FLAT', 'ZZ flat', 12, 1);
