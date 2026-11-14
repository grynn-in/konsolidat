-- gate: build gold_spread_budget assert_trial_balance_period_declared
-- gate: expect assert_trial_balance_period_declared flag 1
-- konsolidat#171 2d (#355 review F1): gold_budget_at_hierarchy_node inner-joins the declared calendar, so a
-- budget for a fiscal year/period konsol has not declared would silently vanish from the hierarchy views.
-- The calendar declares FY2026 P1 only; the budget carries ZZE1 FY2026 P1 (declared) and FY2027 P1 (not).
-- Expected: one row, (ZZ_PLAN, ZZE1, 2027, 1, 'budget', 'period not declared in epm_staging.fiscal_periods').
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open');
INSERT INTO epm_gold.budget_monthly_input
  (scenario_id, data_area_id, fiscal_year, main_account, fiscal_period, amount, layer)
VALUES
  ('ZZ_PLAN', 'ZZE1', 2026, 'ZZ4000', 1, -100, 'base'),
  ('ZZ_PLAN', 'ZZE1', 2027, 'ZZ4000', 1, -100, 'base');
