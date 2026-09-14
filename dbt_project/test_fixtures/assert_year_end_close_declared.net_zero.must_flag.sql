-- assert_year_end_close_declared: must FAIL with exactly 1 result (konsolidat#199, row D8b).
-- The D7 must_flag case (ZZOP, period-end balances, FY2025 P12 then FY2026 P1, no retained-earnings
-- flag, no Closing period) with a second P&L account so the year's P&L NETS TO 0: revenue ZZ4000
-- Cr 100 and expense ZZ5000 Dr 100 at FY2025 P12 (revenue Cr 130 / expense Dr 100 in FY2026); the
-- opening retained earnings ZZ3100 Cr 100 balance the cash in both files. The net result is 0, but
-- both P&L accounts still hold a balance at the year end that the next year's file restarts from 0 —
-- silver_tb_movements closes every P&L key regardless of the net, so the year needs a close and
-- cannot be closed: (ZZOP, 2025) must be named once. A "sum != 0" test stays silent here and lets
-- FY2026 P1 read the two reversals (+100 / -100) plus the new activity as activity.
--   FY2025 P12: cash ZZ1000 100 Dr | ZZ3100 100 Cr | revenue ZZ4000 100 Cr | expense ZZ5000 100 Dr
--   FY2026 P1:  cash ZZ1000 130 Dr | ZZ3100 100 Cr | revenue ZZ4000 130 Cr | expense ZZ5000 100 Dr
-- The live tables may predate the two columns: add them to the scratch clones first.
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
ALTER TABLE epm_staging.main_accounts ADD COLUMN IF NOT EXISTS is_retained_earnings UInt8 DEFAULT 0;
INSERT INTO epm_staging.main_accounts
  (main_account, account_name, chart_of_accounts, parent_account, is_group, account_type, statement_section, sub_section, normal_balance, time_balance, fx_method, is_posting, is_suspended, allow_ic, cf_category, cf_line_item, is_cash, main_account_category, status, is_retained_earnings)
VALUES
  ('ZZ1000', 'ZZ cash', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 1, 'CASH', 'Published', 0),
  ('ZZ3100', 'ZZ retained earnings', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 0),
  ('ZZ4000', 'ZZ revenue', 'ZZCOA', '', 0, 'Revenue', 'Profit and Loss', 'Revenue', 'Credit', 'Period', 'average', 1, 0, 0, '', '', 0, 'REVENUE', 'Published', 0),
  ('ZZ5000', 'ZZ expense', 'ZZCOA', '', 0, 'Expense', 'Profit and Loss', 'Operating Expenses', 'Debit', 'Period', 'average', 1, 0, 0, '', '', 0, 'EXPENSE', 'Published', 0);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2025, 12, 'FY2025-P12', 'Dec 2025', 'Regular', '2025-12-01', '2025-12-31', 'Q4', 'Open'),
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZN1', 'ZZOP', 2025, 12, 'ZZ1000', 100, 0, 'Cash', 'ZZ-TBS-N1', now(), ''),
  ('ZZN1', 'ZZOP', 2025, 12, 'ZZ3100', 0, 100, 'Retained earnings', 'ZZ-TBS-N1', now(), ''),
  ('ZZN1', 'ZZOP', 2025, 12, 'ZZ4000', 0, 100, 'Revenue', 'ZZ-TBS-N1', now(), ''),
  ('ZZN1', 'ZZOP', 2025, 12, 'ZZ5000', 100, 0, 'Expense', 'ZZ-TBS-N1', now(), ''),
  ('ZZN2', 'ZZOP', 2026, 1, 'ZZ1000', 130, 0, 'Cash', 'ZZ-TBS-N2', now(), ''),
  ('ZZN2', 'ZZOP', 2026, 1, 'ZZ4000', 0, 130, 'Revenue', 'ZZ-TBS-N2', now(), ''),
  ('ZZN2', 'ZZOP', 2026, 1, 'ZZ5000', 100, 0, 'Expense', 'ZZ-TBS-N2', now(), ''),
  ('ZZN2', 'ZZOP', 2026, 1, 'ZZ3100', 0, 100, 'Retained earnings', 'ZZ-TBS-N2', now(), '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZN1', 'ZZ-TBS-N1', 'ZZOP', 2025, 12, 4, now(), 'Period-end balance'),
  ('ZZN2', 'ZZ-TBS-N2', 'ZZOP', 2026, 1, 4, now(), 'Period-end balance');
