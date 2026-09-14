-- assert_ytd_at_last_regular_period_equals_annual (konsolidat#199 row D10): the test must PASS on these rows.
--
-- Rule under test: a fiscal year's "annual" total is the sum of its Regular periods' activity; the
-- Closing period (where silver_tb_movements posts the year-end close of a period-end-balance file)
-- is a reclassification of the year's result, not activity, and is left out. The YTD it is compared
-- with is read at the year's last Regular period from the declared calendar, not at a hardcoded 12.
--
-- One ZZ entity (ZZOP), two period-end-balance files a year apart (the D9 closing_period_rates rows
-- without the rates, groups and currencies; the test reads gold_ytd_trial_balance and
-- gold_trial_balance only):
--   FY2025 P12: cash ZZ1000 100 Dr | revenue ZZ4000 100 Cr
--   FY2026 P12: cash ZZ1000 130 Dr | revenue ZZ4000  30 Cr | retained earnings ZZ3100 100 Cr
-- The chart flags ZZ3100 as retained earnings and the calendar has FY2025's Closing period (P13), so
-- the year-end close lands in FY2025 P13: ZZ4000 +100, ZZ3100 -100. Summing every period of FY2025
-- then gives ZZ4000 an annual of 0 against a YTD of -100 at P12 (the old test warned on it); summing
-- the Regular periods only gives -100 = the YTD at the year's last Regular period.
--
-- The gate creates every warehouse table this file names in its scratch schemas with the live DDL. The lineage of
-- gold_trial_balance also reads these ERP-side tables, empty on a trial-balance-only site, so they
-- are named here to exist (empty): epm_raw.general_journal_account_entry_bi_entities,
-- epm_raw.general_journal_entry_bi_entities, epm_raw.ledgers, epm_raw.legal_entities,
-- epm_raw.fiscal_calendar_years, epm_gold.entity_fiscal_calendars, epm_staging.historical_equity_rates,
-- epm_staging.dimension_mappings.
--
-- The live tables may predate the two columns: add them to the scratch clones first.
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
ALTER TABLE epm_staging.main_accounts ADD COLUMN IF NOT EXISTS is_retained_earnings UInt8 DEFAULT 0;
INSERT INTO epm_staging.main_accounts
  (main_account, account_name, chart_of_accounts, parent_account, is_group, account_type, statement_section, sub_section, normal_balance, time_balance, fx_method, is_posting, is_suspended, allow_ic, cf_category, cf_line_item, is_cash, main_account_category, status, is_retained_earnings)
VALUES
  ('ZZ1000', 'ZZ cash', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 1, 'CASH', 'Published', 0),
  ('ZZ3100', 'ZZ retained earnings', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 1),
  ('ZZ4000', 'ZZ revenue', 'ZZCOA', '', 0, 'Revenue', 'Profit and Loss', 'Revenue', 'Credit', 'Period', 'average', 1, 0, 0, '', '', 0, 'REVENUE', 'Published', 0);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2025, 12, 'FY2025-P12', 'Dec 2025', 'Regular', '2025-12-01', '2025-12-31', 'Q4', 'Open'),
  (2025, 13, 'FY2025-P13', 'FY2025 closing', 'Closing', '2025-12-31', '2025-12-31', 'Q4', 'Open'),
  (2026, 12, 'FY2026-P12', 'Dec 2026', 'Regular', '2026-12-01', '2026-12-31', 'Q4', 'Open');
INSERT INTO epm_staging.entities
  (data_area_id, entity_name, parent_entity, is_group, status, accounting_currency, country, erp_source)
VALUES
  ('ZZOP', 'ZZ Operating', 'ZZGRP', 0, 'Active', 'EUR', 'DE', '');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZR1', 'ZZOP', 2025, 12, 'ZZ1000', 100, 0, 'Cash', 'ZZ-TBS-R1', now(), ''),
  ('ZZR1', 'ZZOP', 2025, 12, 'ZZ4000', 0, 100, 'Revenue', 'ZZ-TBS-R1', now(), ''),
  ('ZZR2', 'ZZOP', 2026, 12, 'ZZ1000', 130, 0, 'Cash', 'ZZ-TBS-R2', now(), ''),
  ('ZZR2', 'ZZOP', 2026, 12, 'ZZ4000', 0, 30, 'Revenue', 'ZZ-TBS-R2', now(), ''),
  ('ZZR2', 'ZZOP', 2026, 12, 'ZZ3100', 0, 100, 'Retained earnings', 'ZZ-TBS-R2', now(), '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZR1', 'ZZ-TBS-R1', 'ZZOP', 2025, 12, 2, now(), 'Period-end balance'),
  ('ZZR2', 'ZZ-TBS-R2', 'ZZOP', 2026, 12, 3, now(), 'Period-end balance');
