-- assert_year_end_close_declared: must PASS (konsolidat#199, PR 200 re-review finding 1).
-- A period-end-balance entity with two fiscal years of BALANCE-SHEET-ONLY rows, no Closing period in
-- the calendar and no retained-earnings flag on the chart. Nothing sits in a P&L account at the end of
-- FY2025, so there is nothing to close and the missing Closing period / flag must not block the build.
--   FY2025 P12: cash ZZ1000 100 Dr | loan ZZ2000 100 Cr
--   FY2026 P1:  cash ZZ1000 130 Dr | loan ZZ2000 130 Cr
-- The live tables may predate the two columns: add them to the scratch clones first.
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
ALTER TABLE epm_staging.main_accounts ADD COLUMN IF NOT EXISTS is_retained_earnings UInt8 DEFAULT 0;
INSERT INTO epm_staging.main_accounts
  (main_account, account_name, chart_of_accounts, parent_account, is_group, account_type, statement_section, sub_section, normal_balance, time_balance, fx_method, is_posting, is_suspended, allow_ic, cf_category, cf_line_item, is_cash, main_account_category, status, is_retained_earnings)
VALUES
  ('ZZ1000', 'ZZ cash', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 1, 'CASH', 'Published', 0),
  ('ZZ2000', 'ZZ loan', 'ZZCOA', '', 0, 'Liability', 'Balance Sheet', 'Non-current Liabilities', 'Credit', 'Balance', 'closing', 1, 0, 0, '', '', 0, 'LIABILITY', 'Published', 0);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2025, 12, 'FY2025-P12', 'Dec 2025', 'Regular', '2025-12-01', '2025-12-31', 'Q4', 'Open'),
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZB1', 'ZZOP', 2025, 12, 'ZZ1000', 100, 0, 'Cash', 'ZZ-TBS-B1', now(), ''),
  ('ZZB1', 'ZZOP', 2025, 12, 'ZZ2000', 0, 100, 'Loan', 'ZZ-TBS-B1', now(), ''),
  ('ZZB2', 'ZZOP', 2026, 1, 'ZZ1000', 130, 0, 'Cash', 'ZZ-TBS-B2', now(), ''),
  ('ZZB2', 'ZZOP', 2026, 1, 'ZZ2000', 0, 130, 'Loan', 'ZZ-TBS-B2', now(), '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZB1', 'ZZ-TBS-B1', 'ZZOP', 2025, 12, 2, now(), 'Period-end balance'),
  ('ZZB2', 'ZZ-TBS-B2', 'ZZOP', 2026, 1, 2, now(), 'Period-end balance');
