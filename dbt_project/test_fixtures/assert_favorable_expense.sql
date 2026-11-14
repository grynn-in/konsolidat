-- assert_favorable_expense: must PASS. Every Expense row with a budget and actual below budget is marked
-- favorable: ZZ5000 actual 50 / budget 60 (favorable 1). ZZ4000 is a Revenue row, so it is outside the
-- rule. ZZ7000 is Expense with no budget, so the budget-not-null filter leaves it out (favorable 0).
INSERT INTO epm_gold.gold_variance_analysis
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_pnl,
   dim_cost_center, dim_department, actual_amount, budget_amount, variance_abs, variance_pct, variance_favorable,
   budget_scenario_id)
VALUES
  ('ZZE1', 2026, 1, 'ZZ5000', 'costs', 'Expense', 1, 'ZZCC1', '', 50, 60, -10, NULL, 1, 'BUDGET'),
  ('ZZE1', 2026, 1, 'ZZ4000', 'revenue', 'Revenue', 1, 'ZZCC1', '', 100, 90, 10, NULL, 1, 'BUDGET'),
  ('ZZE1', 2026, 1, 'ZZ7000', 'other costs', 'Expense', 1, 'ZZCC1', '', 50, NULL, 50, NULL, 0, 'BUDGET');
