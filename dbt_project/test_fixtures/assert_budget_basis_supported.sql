-- gate: expect assert_budget_basis_supported pass
-- konsol#348 S2 (R9, narrowed by R10): every budget line is a 'Period movement' line, one of the two
-- bases gold_spread_budget reads, and each (cycle, entity, layer, year) has one basis: nothing flagged.
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 600, 'USD', 'Period movement'),
  ('ZZ-BE-2', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'challenge', 'ZZE1', 2026, 2, 'ZZ4000', 100, 0, 'USD', 'Period movement');
