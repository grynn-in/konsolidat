-- gate: build gold_spread_budget assert_budget_period_declared
-- gate: expect assert_budget_period_declared flag 1
-- konsolidat#171 2d (#355 re-review F1-a): gold_budget_at_hierarchy_node inner-joins the declared calendar, so a
-- budget for a fiscal year/period konsol has not declared would silently vanish from the hierarchy views.
-- The calendar declares FY2026 P1 only; the budget carries ZZE1 FY2026 P1 (declared) and FY2027 P1 (not).
-- Expected: one row, (ZZ_PLAN, ZZE1, 2027, 1, 'period not declared in epm_staging.fiscal_periods'); a WARN, so it never blocks the chain.
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open');
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis, dim_cost_center, dim_department)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_PLAN', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 100, 'USD', 'Period movement', '', ''),
  ('ZZ-BE-2', 'ZZ-CY-2027', 'ZZ_PLAN', 'base', 'ZZE1', 2027, 1, 'ZZ4000', 0, 100, 'USD', 'Period movement', '', '');
