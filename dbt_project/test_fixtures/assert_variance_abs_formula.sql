-- assert_variance_abs_formula: must PASS. variance_abs equals actual - budget on every budgeted row:
-- ZZ4000 100-90=10, ZZ5000 50-60=-10. ZZ7000 has no budget, so the filter leaves it out (its variance_abs
-- 999 would break the formula if it were checked).
INSERT INTO epm_gold.gold_variance_analysis
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_pnl,
   dim_cost_center, dim_department, actual_amount, budget_amount, variance_abs, variance_pct, variance_favorable,
   budget_scenario_id)
VALUES
  ('ZZE1', 2026, 1, 'ZZ4000', 'revenue', 'Revenue', 1, 'ZZCC1', '', 100, 90, 10, NULL, 1, 'BUDGET'),
  ('ZZE1', 2026, 1, 'ZZ5000', 'costs', 'Expense', 1, 'ZZCC1', '', 50, 60, -10, NULL, 1, 'BUDGET'),
  ('ZZE1', 2026, 1, 'ZZ7000', 'other revenue', 'Revenue', 1, 'ZZCC1', '', 50, NULL, 999, NULL, 0, 'BUDGET');
