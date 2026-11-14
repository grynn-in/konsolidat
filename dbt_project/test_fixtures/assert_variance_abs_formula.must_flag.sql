-- gate: expect assert_variance_abs_formula flag 1
-- assert_variance_abs_formula: must FLAG 1. ZZ4000 has actual 100 and budget 90 but variance_abs 25 (formula
-- gives 10), so the test must flag exactly that row. ZZ5000 is correct and ZZ7000 has no budget.
INSERT INTO epm_gold.gold_variance_analysis
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_pnl,
   dim_cost_center, dim_department, actual_amount, budget_amount, variance_abs, variance_pct, variance_favorable,
   budget_scenario_id)
VALUES
  ('ZZE1', 2026, 1, 'ZZ4000', 'revenue', 'Revenue', 1, 'ZZCC1', '', 100, 90, 25, NULL, 1, 'BUDGET'),
  ('ZZE1', 2026, 1, 'ZZ5000', 'costs', 'Expense', 1, 'ZZCC1', '', 50, 60, -10, NULL, 1, 'BUDGET'),
  ('ZZE1', 2026, 1, 'ZZ7000', 'other revenue', 'Revenue', 1, 'ZZCC1', '', 50, NULL, 999, NULL, 0, 'BUDGET');
