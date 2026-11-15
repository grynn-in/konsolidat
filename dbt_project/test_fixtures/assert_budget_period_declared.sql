-- gate: expect assert_budget_period_declared pass
-- konsol#348 PR3 (BUD-10-1): every budget line sits in a declared Regular period, so nothing is flagged. FY2026
-- P1..P2 are Regular, P13 is Closing and holds no budget line. The fact gold_spread_budget is named so it
-- exists, empty.
-- epm_gold.gold_spread_budget
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open'),
  (2026, 2, 'FY2026-P02', 'Feb 2026', 'Regular', '2026-02-01', '2026-02-28', 'Q1', 'Open'),
  (2026, 13, 'FY2026-P13', 'Closing 2026', 'Closing', '2026-12-31', '2026-12-31', 'Q4', 'Open');
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-1', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 10, 'USD', 'Period movement'),
  ('ZZ-BE-2', 'ZZ-CY-1', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 2, 'ZZ4000', 0, 20, 'USD', 'Period movement');
