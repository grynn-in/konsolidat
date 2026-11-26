-- gate: build +assert_period_close_integrity +assert_period_close_quarter_snapshot
-- gate: expect assert_period_close_integrity pass
-- gate: expect assert_period_close_quarter_snapshot pass
-- Period-close family (konsolidat#<this issue>), checks (a), (c), (d), (e) across a year end with every boundary period
-- declared: both tests must PASS on the model as built.
-- Calendar: FY2025 P12 Regular (Q4), P13 Closing and P14 Adjustment (both on 2025-12-31, P12's last day), FY2026 P0
-- Opening (2026-01-01, P1's first day) and P1 Regular (Q1). ZZ3100 is the one is_retained_earnings account.
-- ZZOP files 'Period-end balance':
--   FY2025 P12  cash ZZ1000 100 Dr | revenue ZZ4000 100 Cr
--   FY2026 P0   cash ZZ1000 100 Dr | retained earnings ZZ3100 100 Cr     (the opening balances after the close)
--   FY2026 P1   cash ZZ1000 130 Dr | revenue ZZ4000 30 Cr | retained earnings ZZ3100 100 Cr
-- silver_tb_movements synthesises the #259 close in FY2025 P13 (revenue +100, retained earnings -100; cash carried, no
-- movement). FY2026 P0 then differences to 0 on every key (no phantom opening movement, (e)); P1 is activity only.
-- P14 is declared but not claimed: it produces no row at all (e). Nothing moves the balance sheet in P13 (d).
-- (a) reported P&L YTD = stated: FY2025 P12 revenue -100; FY2026 P1 revenue -30 (the prior year's result is not carried
--     into the new year's P&L).
-- (c) FY2025 Q4 = P12 only (-100): gold_pnl_quarterly puts the P13 close under 'CLS', not Q4; FY2026 Q1 = -30.
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
  ('ZZ3100', 'ZZ retained earnings', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 1),
  ('ZZ4000', 'ZZ revenue', 'ZZCOA', '', 0, 'Revenue', 'Profit and Loss', 'Revenue', 'Credit', 'Period', 'average', 1, 0, 0, '', '', 0, 'REVENUE', 'Published', 0);
INSERT INTO epm_staging.entities
  (data_area_id, entity_name, parent_entity, is_group, status, accounting_currency, country, erp_source)
VALUES
  ('ZZOP', 'ZZ Operating', 'ZZGRP', 0, 'Active', 'EUR', 'DE', '');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2025, 12, 'FY2025-P12', 'Dec 2025', 'Regular', '2025-12-01', '2025-12-31', 'Q4', 'Open'),
  (2025, 13, 'FY2025-P13', 'FY2025 closing', 'Closing', '2025-12-31', '2025-12-31', 'Q4', 'Open'),
  (2025, 14, 'FY2025-P14', 'FY2025 adjustment', 'Adjustment', '2025-12-31', '2025-12-31', 'Q4', 'Open'),
  (2026, 0, 'FY2026-P00', 'FY2026 opening', 'Opening', '2026-01-01', '2026-01-01', 'Q1', 'Open'),
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZC1', 'ZZOP', 2025, 12, 'ZZ1000', 100, 0, 'Cash', 'ZZ-TBS-C1', now(), ''),
  ('ZZC1', 'ZZOP', 2025, 12, 'ZZ4000', 0, 100, 'Revenue', 'ZZ-TBS-C1', now(), ''),
  ('ZZC0', 'ZZOP', 2026, 0, 'ZZ1000', 100, 0, 'Cash', 'ZZ-TBS-C0', now(), ''),
  ('ZZC0', 'ZZOP', 2026, 0, 'ZZ3100', 0, 100, 'Retained earnings', 'ZZ-TBS-C0', now(), ''),
  ('ZZC2', 'ZZOP', 2026, 1, 'ZZ1000', 130, 0, 'Cash', 'ZZ-TBS-C2', now(), ''),
  ('ZZC2', 'ZZOP', 2026, 1, 'ZZ4000', 0, 30, 'Revenue', 'ZZ-TBS-C2', now(), ''),
  ('ZZC2', 'ZZOP', 2026, 1, 'ZZ3100', 0, 100, 'Retained earnings', 'ZZ-TBS-C2', now(), '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZC1', 'ZZ-TBS-C1', 'ZZOP', 2025, 12, 2, now(), 'Period-end balance'),
  ('ZZC0', 'ZZ-TBS-C0', 'ZZOP', 2026, 0, 2, now(), 'Period-end balance'),
  ('ZZC2', 'ZZ-TBS-C2', 'ZZOP', 2026, 1, 3, now(), 'Period-end balance');
