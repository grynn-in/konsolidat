-- gate: build silver_gl_entries assert_tb_submission_period_start_not_epoch
-- gate: expect assert_tb_submission_period_start_not_epoch flag 2
-- konsolidat#189 PR3 (konsol#348, A11): a trial-balance submission in a period the calendar does not declare
-- KEEPS its rows in silver_gl_entries, dated 1970-01-01 (Date's default: the declared-periods LEFT JOIN
-- misses under join_use_nulls=0), and this test names both of them. Nothing is invented for the period.
-- Before A11, silver_gl_entries dated the period at the first day of the calendar month its number names
-- (the retired calendar-month macro), so the rows carried a plausible date and this test passed.
--
-- The calendar declares FY2026 P1 only (April 2025); the submission is for FY2026 P2. silver_tb_movements is
-- seeded (it is not in the selector).
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, is_equity, fx_method, is_posting, is_retained_earnings, uses_historical_rate)
VALUES
  ('ZZ1000', 'ZZ cash', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ3000', 'ZZ capital', 'Equity', 'Equity', 0, 1, 1, 'closing', 1, 0, 0);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Apr 2025', 'Regular', '2025-04-01', '2025-04-30', 'Q1', 'Open');
INSERT INTO epm_silver.silver_tb_movements
  (data_area_id, fiscal_year, fiscal_period, main_account, partner_data_area_id, dim_business_unit, dim_cost_center, dim_department, amount_basis, batch_id, submission_name, description, source_net_amount, movement_amount, debit_amount, credit_amount, movement_kind)
VALUES
  ('ZZE1', 2026, 2, 'ZZ1000', '', '', '', '', 'Period movement', 'ZZB1', 'ZZ-TBS-1', 'ZZ cash', 100, 100, 100, 0, 'activity'),
  ('ZZE1', 2026, 2, 'ZZ3000', '', '', '', '', 'Period movement', 'ZZB1', 'ZZ-TBS-1', 'ZZ capital', -100, -100, 0, 100, 'activity');
