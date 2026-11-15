-- gate: expect assert_budget_ytd_hand_table flag 5
-- konsol#348 S2 (R10, Q15-c): the hand table of budget_raw_ytd.sql, asserted as literals. Same stated
-- lines (one is enough to open the cycle), but a seeded spread that is wrong: ZZ4000 base P2 holds -250
-- (hand: -150), and ZZ4000 base P3, ZZ6000 P3 (-200) and challenge P1 and P3 (both 0) are missing. 5 results.
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-HAND', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 100, 'USD', 'Year-to-date movement');
-- The fact carries cycle and currency since S3 B4; the live table may predate them: add them to the clone.
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS cycle String DEFAULT '';
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS currency String DEFAULT '';
INSERT INTO epm_gold.gold_spread_budget
  (scenario_id, cycle, data_area_id, fiscal_year, fiscal_period, main_account, layer, currency, annual_amount, spread_profile_id, profile_name, period_weight, period_amount, submitted_by)
VALUES
  ('ZZ_PLAN_2026', 'ZZ-CY-HAND', 'ZZE1', 2026, 1, 'ZZ4000', 'base', 'USD', -350, 'manual', 'Manual (as-entered)', 0.2857, -100, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-HAND', 'ZZE1', 2026, 2, 'ZZ4000', 'base', 'USD', -350, 'manual', 'Manual (as-entered)', 0.7143, -250, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-HAND', 'ZZE1', 2026, 1, 'ZZ6000', 'base', 'USD', 200, 'manual', 'Manual (as-entered)', 0.4, 80, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-HAND', 'ZZE1', 2026, 2, 'ZZ6000', 'base', 'USD', 200, 'manual', 'Manual (as-entered)', 0.6, 120, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-HAND', 'ZZE1', 2026, 2, 'ZZ4000', 'challenge', 'USD', -50, 'manual', 'Manual (as-entered)', 1, -50, '');
