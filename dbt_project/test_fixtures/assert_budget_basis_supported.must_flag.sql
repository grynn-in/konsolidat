-- gate: expect assert_budget_basis_supported flag 1
-- konsol#348 S2 (R9, narrowed by R10): one 'Period-end balance' line, which gold_spread_budget does not
-- read (Q15-c: a balance needs an opening balance, an open policy question). The test names it. Its
-- layer holds no other basis, and the 'Period movement' line in the base layer is not flagged.
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 600, 'USD', 'Period movement'),
  ('ZZ-BE-2', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'challenge', 'ZZE1', 2026, 3, 'ZZ1000', 1800, 0, 'USD', 'Period-end balance');
