-- gate: expect assert_budget_basis_supported flag 1
-- konsol#348 S2 (R10, Q15-c): the base layer of ZZ-CY-2026 / ZZE1 / 2026 holds a 'Period movement' line
-- in P1 and a 'Year-to-date movement' line in P2. Each basis is read, but a YTD figure cannot be
-- differenced against a movement, so the (cycle, entity, layer, year) is named once. The challenge layer,
-- YTD throughout, is not flagged. On R9's test this flags 2 (both YTD lines), not 1.
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 600, 'USD', 'Period movement'),
  ('ZZ-BE-2', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 2, 'ZZ6000', 0, 1300, 'USD', 'Year-to-date movement'),
  ('ZZ-BE-3', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'challenge', 'ZZE1', 2026, 2, 'ZZ4000', 100, 0, 'USD', 'Year-to-date movement');
