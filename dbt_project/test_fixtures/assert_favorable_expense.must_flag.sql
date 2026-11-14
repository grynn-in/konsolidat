-- gate: expect assert_favorable_expense flag 1
-- assert_favorable_expense: must FLAG 1. ZZ5000 is Expense with actual 50 below budget 60, but it is
-- marked unfavorable (variance_favorable 0), so the test must flag exactly that row. The other rows are
-- the same as the PASS fixture and must not match: a Revenue row, and an Expense row with no budget.
INSERT INTO epm_gold.gold_variance_analysis
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_pnl,
   dim_cost_center, dim_department, actual_amount, budget_amount, variance_abs, variance_pct, variance_favorable,
   budget_scenario_id)
VALUES
  ('ZZE1', 2026, 1, 'ZZ5000', 'costs', 'Expense', 1, 'ZZCC1', '', 50, 60, -10, NULL, 0, 'BUDGET'),
  ('ZZE1', 2026, 1, 'ZZ4000', 'revenue', 'Revenue', 1, 'ZZCC1', '', 100, 90, 10, NULL, 1, 'BUDGET'),
  ('ZZE1', 2026, 1, 'ZZ7000', 'other costs', 'Expense', 1, 'ZZCC1', '', 50, NULL, 50, NULL, 0, 'BUDGET');
