-- gate: expect assert_budget_ytd_periods_contiguous flag 3
-- konsol#348 S2 (Q15-c, no silent fallback): a YTD scope (cycle, scenario, layer, entity, year) must
-- state periods exactly 1..max. ZZ-CY-GAP states P1, P2, P3, P5 (P4 missing: P5 would be YTD5 - YTD3):
-- flagged. ZZ-CY-LATE (base) starts at P2 (P2 would merge P1..P2): flagged. ZZ-CY-LATE (challenge)
-- states P1, P2 only: not flagged. ZZ-CY-GAP challenge states P1..P2, P4: flagged. 3 in all.
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-GAP', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 10, 'USD', 'Year-to-date movement'),
  ('ZZ-BE-1', 'ZZ-CY-GAP', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 2, 'ZZ4000', 0, 20, 'USD', 'Year-to-date movement'),
  ('ZZ-BE-1', 'ZZ-CY-GAP', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 3, 'ZZ4000', 0, 30, 'USD', 'Year-to-date movement'),
  ('ZZ-BE-1', 'ZZ-CY-GAP', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 5, 'ZZ4000', 0, 50, 'USD', 'Year-to-date movement'),
  ('ZZ-BE-2', 'ZZ-CY-GAP', 'ZZ_PLAN_2026', 'challenge', 'ZZE1', 2026, 1, 'ZZ4000', 0, 10, 'USD', 'Year-to-date movement'),
  ('ZZ-BE-2', 'ZZ-CY-GAP', 'ZZ_PLAN_2026', 'challenge', 'ZZE1', 2026, 2, 'ZZ4000', 0, 20, 'USD', 'Year-to-date movement'),
  ('ZZ-BE-2', 'ZZ-CY-GAP', 'ZZ_PLAN_2026', 'challenge', 'ZZE1', 2026, 4, 'ZZ4000', 0, 40, 'USD', 'Year-to-date movement'),
  ('ZZ-BE-3', 'ZZ-CY-LATE', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 2, 'ZZ4000', 0, 20, 'USD', 'Year-to-date movement'),
  ('ZZ-BE-3', 'ZZ-CY-LATE', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 3, 'ZZ4000', 0, 30, 'USD', 'Year-to-date movement'),
  ('ZZ-BE-4', 'ZZ-CY-LATE', 'ZZ_PLAN_2026', 'challenge', 'ZZE1', 2026, 1, 'ZZ4000', 0, 10, 'USD', 'Year-to-date movement'),
  ('ZZ-BE-4', 'ZZ-CY-LATE', 'ZZ_PLAN_2026', 'challenge', 'ZZE1', 2026, 2, 'ZZ4000', 0, 20, 'USD', 'Year-to-date movement');
