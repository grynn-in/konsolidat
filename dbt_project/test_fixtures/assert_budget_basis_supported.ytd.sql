-- gate: expect assert_budget_basis_supported pass
-- konsol#348 S2 (R10, Q15-c): 'Year-to-date movement' lines are read (converted to movements by
-- gold_spread_budget), so they are not flagged. The base layer is YTD throughout and the challenge layer
-- is 'Period movement': one basis per (cycle, entity, layer, year), so nothing is mixed either.
-- On R9's test, which flagged every basis but 'Period movement', this flags 2.
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 600, 'USD', 'Year-to-date movement'),
  ('ZZ-BE-2', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 2, 'ZZ4000', 0, 1300, 'USD', 'Year-to-date movement'),
  ('ZZ-BE-3', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'challenge', 'ZZE1', 2026, 2, 'ZZ4000', 100, 0, 'USD', 'Period movement');
