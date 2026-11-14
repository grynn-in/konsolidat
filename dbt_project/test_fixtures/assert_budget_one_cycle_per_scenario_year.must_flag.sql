-- gate: expect assert_budget_one_cycle_per_scenario_year flag 1
-- konsol#348 S2 (Q16-c): gold_spread_budget sums manual lines without the cycle, so two Cycles with
-- lines on one (scenario, year) would double the budget silently. Scenario ZZ_PLAN_2026 FY2026 has
-- lines in cycles ZZ-CY-A and ZZ-CY-B on the same account: 1 result. Scenario ZZ_PLAN_2027 has two
-- lines in one cycle and is not flagged.
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-A', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 100, 'USD', 'Period movement'),
  ('ZZ-BE-2', 'ZZ-CY-B', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 100, 'USD', 'Period movement'),
  ('ZZ-BE-3', 'ZZ-CY-C', 'ZZ_PLAN_2027', 'base', 'ZZE1', 2027, 1, 'ZZ4000', 0, 100, 'USD', 'Period movement'),
  ('ZZ-BE-3', 'ZZ-CY-C', 'ZZ_PLAN_2027', 'base', 'ZZE1', 2027, 2, 'ZZ4000', 0, 100, 'USD', 'Period movement');
