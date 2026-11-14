-- gate: expect assert_budget_ytd_reconciles flag 2
-- konsol#348 S2 (R10): a spread that carries year-to-date lines AS IF they were movements does not
-- reconcile, and the test names it. One base key ZZ4000, stated YTD P1 -100, P2 -250. The seeded spread
-- holds -100 at P1 (right: the first period is its YTD) and -250 at P2 (wrong: the movement is -150),
-- so the running sum at P2 is -350 against a stated -250: 1 result. Key ZZ6000 states 80 at P1 and
-- vanishes in P2 (YTD 0); the seeded spread holds only its 80 and no reversal, so the running sum at
-- P2 is 80 against 0: 1 result. 2 in all.
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 100, 'USD', 'Year-to-date movement'),
  ('ZZ-BE-2', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 2, 'ZZ4000', 0, 250, 'USD', 'Year-to-date movement'),
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ6000', 80, 0, 'USD', 'Year-to-date movement');
INSERT INTO epm_gold.gold_spread_budget
  (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, layer, annual_amount, spread_profile_id, profile_name, period_weight, period_amount, submitted_by)
VALUES
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 1, 'ZZ4000', 'base', -350, 'manual', 'Manual (as-entered)', 0.2857, -100, ''),
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 2, 'ZZ4000', 'base', -350, 'manual', 'Manual (as-entered)', 0.7143, -250, ''),
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 1, 'ZZ6000', 'base', 80, 'manual', 'Manual (as-entered)', 1, 80, '');
