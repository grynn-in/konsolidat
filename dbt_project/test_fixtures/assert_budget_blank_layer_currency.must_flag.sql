-- gate: expect assert_budget_blank_layer_currency flag 4
-- konsol#348 S2 (Q13-a): every budget row declares its layer and currency. A blank is reported, never
-- defaulted. Two budget_entries rows (blank layer; blank currency) and two budget_annual_input rows
-- (blank layer; blank currency) are flagged: 4. The complete rows are not.
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_PLAN_2026', '', 'ZZE1', 2026, 1, 'ZZ4000', 0, 100, 'USD', 'Period movement'),
  ('ZZ-BE-2', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 100, '', 'Period movement'),
  ('ZZ-BE-3', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ6000', 0, 100, 'USD', 'Period movement');
INSERT INTO epm_gold.budget_annual_input
  (scenario_id, data_area_id, fiscal_year, main_account, layer, currency, annual_amount, spread_profile_id, submitted_by)
VALUES
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ7000', '', 'USD', 1200, 'ZZ_FLAT', 'zz'),
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ7100', 'base', '', 1200, 'ZZ_FLAT', 'zz'),
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ7200', 'base', 'USD', 1200, 'ZZ_FLAT', 'zz');
