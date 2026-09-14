-- assert_year_end_close_declared: must FAIL with exactly 1 result (konsolidat#199).
-- The same two period-end-balance files as silver_tb_movements.year_end_close.sql (ZZOP, FY2025 P12
-- then FY2026 P1), but the chart flags no retained-earnings account and the calendar has no Closing
-- period for FY2025: the year needs a close and cannot be closed, so (ZZOP, 2025) is named once.
-- The live tables may predate the two columns: add them to the scratch clones first.
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
ALTER TABLE epm_staging.main_accounts ADD COLUMN IF NOT EXISTS is_retained_earnings UInt8 DEFAULT 0;
INSERT INTO epm_staging.main_accounts
  (main_account, account_name, chart_of_accounts, parent_account, is_group, account_type, statement_section, sub_section, normal_balance, time_balance, fx_method, is_posting, is_suspended, allow_ic, cf_category, cf_line_item, is_cash, main_account_category, status, is_retained_earnings)
VALUES
  ('ZZ1000', 'ZZ cash', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 1, 'CASH', 'Published', 0),
  ('ZZ3100', 'ZZ retained earnings', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 0),
  ('ZZ4000', 'ZZ revenue', 'ZZCOA', '', 0, 'Revenue', 'Profit and Loss', 'Revenue', 'Credit', 'Period', 'average', 1, 0, 0, '', '', 0, 'REVENUE', 'Published', 0);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2025, 12, 'FY2025-P12', 'Dec 2025', 'Regular', '2025-12-01', '2025-12-31', 'Q4', 'Open'),
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZY1', 'ZZOP', 2025, 12, 'ZZ1000', 100, 0, 'Cash', 'ZZ-TBS-Y1', now(), ''),
  ('ZZY1', 'ZZOP', 2025, 12, 'ZZ4000', 0, 100, 'Revenue', 'ZZ-TBS-Y1', now(), ''),
  ('ZZY2', 'ZZOP', 2026, 1, 'ZZ1000', 130, 0, 'Cash', 'ZZ-TBS-Y2', now(), ''),
  ('ZZY2', 'ZZOP', 2026, 1, 'ZZ4000', 0, 30, 'Revenue', 'ZZ-TBS-Y2', now(), ''),
  ('ZZY2', 'ZZOP', 2026, 1, 'ZZ3100', 0, 100, 'Retained earnings', 'ZZ-TBS-Y2', now(), '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZY1', 'ZZ-TBS-Y1', 'ZZOP', 2025, 12, 2, now(), 'Period-end balance'),
  ('ZZY2', 'ZZ-TBS-Y2', 'ZZOP', 2026, 1, 3, now(), 'Period-end balance');
