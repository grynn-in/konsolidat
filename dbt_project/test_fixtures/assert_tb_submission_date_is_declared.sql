-- gate: build silver_gl_entries assert_tb_submission_date_is_declared
-- gate: expect assert_tb_submission_date_is_declared pass
-- konsolidat#189 PR3 (konsol#348, A10): must PASS once a trial-balance submission row is dated at its declared
-- period's start_date. An April-March site: FY2026 P1 is 2025-04-01 .. 2025-04-30 in epm_staging.fiscal_periods,
-- and no per-entity calendar exists (konsol#577 removed that mapping). Before A11 silver_gl_entries fell back to a
-- calendar-month macro, which dated P1 at 2026-01-01, so the test flagged the row.
--
-- silver_tb_movements is seeded (it is not in the selector).
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
  ('ZZE1', 2026, 1, 'ZZ1000', '', '', '', '', 'Period movement', 'ZZB1', 'ZZ-TBS-1', 'ZZ cash', 100, 100, 100, 0, 'activity'),
  ('ZZE1', 2026, 1, 'ZZ3000', '', '', '', '', 'Period movement', 'ZZB1', 'ZZ-TBS-1', 'ZZ capital', -100, -100, 0, 100, 'activity');
