-- gate: build +assert_period_close_ytd_spine +assert_period_close_integrity +assert_period_close_quarter_snapshot
-- gate: expect assert_period_close_ytd_spine pass
-- gate: expect assert_period_close_integrity pass
-- gate: expect assert_period_close_quarter_snapshot pass
-- Period-close family (konsolidat#397), checks (a), (b) and (c) on a 'Year-to-date movement' entity: all three
-- tests must PASS on the model as built.
-- One ZZ entity (ZZOP), FY2026 P1-P3, all declared Regular in Q1; each batch a balanced set of YTD figures:
--   ZZ1000 cash       150 Dr | 170 Dr | 230 Dr
--   ZZ2000 loan        50 Cr |  30 Cr | absent   -> P3 movement +30: the reversal of a vanished key (b)
--   ZZ4000 revenue    100 Cr | 180 Cr | 290 Cr   -> P&L carried forward, never cleared at a period end (a)
--   ZZ5000 expense    absent |  40 Dr |  60 Dr   -> P2 movement +40: a new key starts from zero (b)
-- Expected movements: P1 +150/-50/-100; P2 +20/+20/-80/+40; P3 +60/+30/-110/+20.
-- (a) reported P&L YTD = stated YTD in every period (revenue -100/-180/-290, expense 0/40/60).
-- (c) Q1 from the calendar (P1-P3) = gold_pnl_quarterly Q1 (revenue -290, expense 60), and the YTD at Q1's last Regular
--     period P3 = the sum of P1-P3.
--
-- The lineage of gold_ytd_trial_balance also reads these ERP-side tables, empty on a trial-balance-only site, so they
-- are named here to exist (empty): epm_raw.general_journal_account_entry_bi_entities,
-- epm_raw.general_journal_entry_bi_entities, epm_raw.ledgers, epm_raw.legal_entities,
-- epm_raw.fiscal_calendar_years, epm_staging.historical_equity_rates,
-- epm_staging.dimension_mappings.
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
ALTER TABLE epm_staging.main_accounts ADD COLUMN IF NOT EXISTS is_retained_earnings UInt8 DEFAULT 0;
INSERT INTO epm_staging.main_accounts
  (main_account, account_name, chart_of_accounts, parent_account, is_group, account_type, statement_section, sub_section, normal_balance, time_balance, fx_method, is_posting, is_suspended, allow_ic, cf_category, cf_line_item, is_cash, main_account_category, status, is_retained_earnings)
VALUES
  ('ZZ1000', 'ZZ cash', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 1, 'CASH', 'Published', 0),
  ('ZZ2000', 'ZZ loan', 'ZZCOA', '', 0, 'Liability', 'Balance Sheet', 'Current Liabilities', 'Credit', 'Balance', 'closing', 1, 0, 0, '', '', 0, 'LIABILITY', 'Published', 0),
  ('ZZ3100', 'ZZ retained earnings', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 1),
  ('ZZ4000', 'ZZ revenue', 'ZZCOA', '', 0, 'Revenue', 'Profit and Loss', 'Revenue', 'Credit', 'Period', 'average', 1, 0, 0, '', '', 0, 'REVENUE', 'Published', 0),
  ('ZZ5000', 'ZZ expense', 'ZZCOA', '', 0, 'Expense', 'Profit and Loss', 'Operating Expenses', 'Debit', 'Period', 'average', 1, 0, 0, '', '', 0, 'EXPENSE', 'Published', 0);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open'),
  (2026, 2, 'FY2026-P02', 'Feb 2026', 'Regular', '2026-02-01', '2026-02-28', 'Q1', 'Open'),
  (2026, 3, 'FY2026-P03', 'Mar 2026', 'Regular', '2026-03-01', '2026-03-31', 'Q1', 'Open');
INSERT INTO epm_staging.entities
  (data_area_id, entity_name, parent_entity, is_group, status, accounting_currency, country, erp_source)
VALUES
  ('ZZOP', 'ZZ Operating', 'ZZGRP', 0, 'Active', 'EUR', 'DE', '');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZY1', 'ZZOP', 2026, 1, 'ZZ1000', 150, 0, 'Cash', 'ZZ-TBS-Y1', now(), ''),
  ('ZZY1', 'ZZOP', 2026, 1, 'ZZ2000', 0, 50, 'Loan', 'ZZ-TBS-Y1', now(), ''),
  ('ZZY1', 'ZZOP', 2026, 1, 'ZZ4000', 0, 100, 'Revenue', 'ZZ-TBS-Y1', now(), ''),
  ('ZZY2', 'ZZOP', 2026, 2, 'ZZ1000', 170, 0, 'Cash', 'ZZ-TBS-Y2', now(), ''),
  ('ZZY2', 'ZZOP', 2026, 2, 'ZZ2000', 0, 30, 'Loan', 'ZZ-TBS-Y2', now(), ''),
  ('ZZY2', 'ZZOP', 2026, 2, 'ZZ4000', 0, 180, 'Revenue', 'ZZ-TBS-Y2', now(), ''),
  ('ZZY2', 'ZZOP', 2026, 2, 'ZZ5000', 40, 0, 'Expense', 'ZZ-TBS-Y2', now(), ''),
  ('ZZY3', 'ZZOP', 2026, 3, 'ZZ1000', 230, 0, 'Cash', 'ZZ-TBS-Y3', now(), ''),
  ('ZZY3', 'ZZOP', 2026, 3, 'ZZ4000', 0, 290, 'Revenue', 'ZZ-TBS-Y3', now(), ''),
  ('ZZY3', 'ZZOP', 2026, 3, 'ZZ5000', 60, 0, 'Expense', 'ZZ-TBS-Y3', now(), '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZY1', 'ZZ-TBS-Y1', 'ZZOP', 2026, 1, 3, now(), 'Year-to-date movement'),
  ('ZZY2', 'ZZ-TBS-Y2', 'ZZOP', 2026, 2, 4, now(), 'Year-to-date movement'),
  ('ZZY3', 'ZZ-TBS-Y3', 'ZZOP', 2026, 3, 3, now(), 'Year-to-date movement');
