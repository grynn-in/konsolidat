-- konsol#255 row 17: the SECOND symptom of the close's contradiction — a P&L
-- account that a file splits across declared dimension values is never reversed
-- by the year-end close at all, so the next year's first period reads last
-- year's result as activity.
--
-- The twin of assert_year_end_close_invents_no_movement.must_flag.sql, which
-- splits BALANCE-SHEET accounts and measures the invention. This one splits the
-- P&L accounts and measures the under-close. Its own entity ZZDL and its own
-- chart ZZLCOA, so it is run on its own: silver_tb_movements needs EXACTLY ONE
-- account flagged is_retained_earnings across the chart, and two fixtures in one
-- run would declare two and close nothing.
--
--   FY2024 P12 (period-end balances)
--     ZZ6000  '' / ''                100 Dr     ZZ7000  '' / ''            50 Cr
--     ZZ9000  CC30 / DEPT-MFG         48 Cr     ZZ9000  CC40 / DEPT-RND    32 Cr
--     ZZ9500  CC30 / DEPT-MFG         18 Dr     ZZ9500  CC40 / DEPT-RND    12 Dr
--     (Dr 130 / Cr 130; the year's result is a profit of 50, and ALL of it sits
--      in accounts the file splits across two dimension values)
--
--   FY2025 P1 (period-end balances, P&L reset, result moved to ZZ8100)
--     ZZ6000  '' / ''                100 Dr     ZZ7000  '' / ''            50 Cr
--     ZZ8100  '' / ''                 50 Cr
--     (Dr 100 / Cr 100)
--
-- The entity never claims FY2024 P13 and the calendar declares it 'Closing', so
-- the model synthesises the close there.
--
-- What a correct close posts at FY2024 P13: the P&L reversed — ZZ9000 +48 and
-- +32, ZZ9500 -18 and -12 — and the result into retained earnings as ONE
-- undimensioned line, ZZ8100 -50 (the decision of 23 September 2026: "one lump,
-- no dimensions"; the dimension values the profit came from are NOT carried into
-- retained earnings). FY2024 P13 then sums to zero, and FY2025 P1 has no P&L
-- activity at all.
--
-- MEASURED BEFORE THE FIX, and the finding: close_spine gives the close row
-- BLANK dimension values while row 7b's lagInFrame is widened, so the close row
-- of a split P&L account (source 0, because it is a P&L key) is differenced
-- against the BLANK slice's previous figure — 0, because a split account has no
-- blank slice. movement 0 and has_source 0, so the row is dropped and nothing is
-- reversed. Two periods then fail to balance:
--     2024 13   -50.00   (only the retained-earnings line was posted)
--     2025  1   +50.00   (ZZ9000 +48 +32, ZZ9500 -18 -12, as 'activity')
-- assert_tb_movements_balance returns both rows. Nothing about this fixture is
-- unbalanced at source: assert_tb_submission_batches_balance passes on it.
--
-- The live tables may predate these columns: add them to the scratch clone first
-- (same guard the other fixtures use for amount_basis).
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS partner_data_area_id String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS dim_business_unit String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS dim_cost_center String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS dim_department String DEFAULT '';
ALTER TABLE epm_staging.main_accounts ADD COLUMN IF NOT EXISTS is_retained_earnings UInt8 DEFAULT 0;
INSERT INTO epm_staging.main_accounts
  (main_account, account_name, chart_of_accounts, parent_account, is_group, account_type, statement_section, sub_section, normal_balance, time_balance, fx_method, is_posting, is_suspended, allow_ic, cf_category, cf_line_item, is_cash, main_account_category, status, is_retained_earnings)
VALUES
  ('ZZ6000', 'ZZ trade receivables', 'ZZLCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 0, 'RECEIVABLES', 'Published', 0),
  ('ZZ7000', 'ZZ trade payables', 'ZZLCOA', '', 0, 'Liability', 'Balance Sheet', 'Current Liabilities', 'Credit', 'Balance', 'closing', 1, 0, 0, '', '', 0, 'PAYABLES', 'Published', 0),
  ('ZZ8100', 'ZZ retained earnings', 'ZZLCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 1),
  ('ZZ9000', 'ZZ services revenue', 'ZZLCOA', '', 0, 'Revenue', 'Profit and Loss', 'Revenue', 'Credit', 'Period', 'average', 1, 0, 0, '', '', 0, 'REVENUE', 'Published', 0),
  ('ZZ9500', 'ZZ operating expense', 'ZZLCOA', '', 0, 'Expense', 'Profit and Loss', 'Operating Expenses', 'Debit', 'Period', 'average', 1, 0, 0, '', '', 0, 'OPEX', 'Published', 0);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2024, 12, 'FY2024-P12', 'Dec 2024', 'Regular', '2024-12-01', '2024-12-31', 'Q4', 'Open'),
  (2024, 13, 'FY2024-P13', 'FY2024 closing', 'Closing', '2024-12-31', '2024-12-31', 'Q4', 'Open'),
  (2025, 1, 'FY2025-P01', 'Jan 2025', 'Regular', '2025-01-01', '2025-01-31', 'Q1', 'Open');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id, dim_business_unit, dim_cost_center, dim_department)
VALUES
  ('ZZDL1', 'ZZDL', 2024, 12, 'ZZ6000', 100, 0, 'Trade receivables', 'ZZ-DIMPNL-1', now(), '', '', '', ''),
  ('ZZDL1', 'ZZDL', 2024, 12, 'ZZ7000', 0, 50, 'Trade payables', 'ZZ-DIMPNL-1', now(), '', '', '', ''),
  ('ZZDL1', 'ZZDL', 2024, 12, 'ZZ9000', 0, 48, 'Services revenue', 'ZZ-DIMPNL-1', now(), '', 'BU-SOUTH', 'CC30', 'DEPT-MFG'),
  ('ZZDL1', 'ZZDL', 2024, 12, 'ZZ9000', 0, 32, 'Services revenue', 'ZZ-DIMPNL-1', now(), '', 'BU-SOUTH', 'CC40', 'DEPT-RND'),
  ('ZZDL1', 'ZZDL', 2024, 12, 'ZZ9500', 18, 0, 'Operating expense', 'ZZ-DIMPNL-1', now(), '', 'BU-SOUTH', 'CC30', 'DEPT-MFG'),
  ('ZZDL1', 'ZZDL', 2024, 12, 'ZZ9500', 12, 0, 'Operating expense', 'ZZ-DIMPNL-1', now(), '', 'BU-SOUTH', 'CC40', 'DEPT-RND'),
  ('ZZDL2', 'ZZDL', 2025, 1, 'ZZ6000', 100, 0, 'Trade receivables', 'ZZ-DIMPNL-2', now(), '', '', '', ''),
  ('ZZDL2', 'ZZDL', 2025, 1, 'ZZ7000', 0, 50, 'Trade payables', 'ZZ-DIMPNL-2', now(), '', '', '', ''),
  ('ZZDL2', 'ZZDL', 2025, 1, 'ZZ8100', 0, 50, 'Retained earnings', 'ZZ-DIMPNL-2', now(), '', '', '', '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZDL1', 'ZZ-DIMPNL-1', 'ZZDL', 2024, 12, 6, now(), 'Period-end balance'),
  ('ZZDL2', 'ZZ-DIMPNL-2', 'ZZDL', 2025, 1, 3, now(), 'Period-end balance');
