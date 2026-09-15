-- konsolidat#220: a reporting hierarchy whose members are dated. A member row is one tranche of a code, valid
-- from member_effective_from to member_effective_to (open = 2299-12-31); a renamed, moved or ended node is a
-- second tranche of the same code. The closure and every node model must resolve the tree as it was in a period.
--
-- Hierarchy ZZ_DIV over dim_business_unit:
--   ZZ_ROOT group 2010-01-01 .. open
--   ZZ_A    group 2010-01-01 .. 2024-12-31 "Alpha"      } a rename: two tranches of one code
--   ZZ_A    group 2025-01-01 .. open       "Alpha New"  }
--   ZZ_B    group 2010-01-01 .. open
--   ZZ_E    group 2017-01-01 .. 2024-12-31               (ended)
--   ZZ_G    group 2013-04-01 .. 2020-06-03               (disposed)
--   ZZ_EX   leaf under ZZ_E 2017-01-01 .. 2024-12-31    } a move: two tranches of one code
--   ZZ_EX   leaf under ZZ_B 2025-01-01 .. open          }
--   ZZ_GX   leaf under ZZ_G 2013-04-01 .. 2020-06-03
--   ZZ_AX   leaf under ZZ_A 2010-01-01 .. open
--
-- The live table may predate the two tranche columns: add them first.
ALTER TABLE epm_staging.reporting_hierarchies ADD COLUMN IF NOT EXISTS member_effective_from Date32 DEFAULT '1900-01-01';
ALTER TABLE epm_staging.reporting_hierarchies ADD COLUMN IF NOT EXISTS member_effective_to Date32 DEFAULT '2299-12-31';
-- A table that already has them as plain Date (1970-01-01..2149-06-06 clamps both ends) becomes Date32.
ALTER TABLE epm_staging.reporting_hierarchies MODIFY COLUMN member_effective_from Date32 DEFAULT '1900-01-01';
ALTER TABLE epm_staging.reporting_hierarchies MODIFY COLUMN member_effective_to Date32 DEFAULT '2299-12-31';
INSERT INTO epm_staging.reporting_hierarchies
  (hierarchy_name, dimension, member_code, member_label, parent_member_code, is_group, hierarchy_level, path, effective_from, effective_to, is_default, status, member_effective_from, member_effective_to)
VALUES
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_ROOT', 'ZZ root', '', 1, 1, 'ZZ_ROOT', '', '', 1, 'Published', '2010-01-01', '2299-12-31'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_A', 'Alpha', 'ZZ_ROOT', 1, 2, 'ZZ_ROOT/ZZ_A', '', '', 1, 'Published', '2010-01-01', '2024-12-31'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_A', 'Alpha New', 'ZZ_ROOT', 1, 2, 'ZZ_ROOT/ZZ_A', '', '', 1, 'Published', '2025-01-01', '2299-12-31'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_B', 'ZZ B', 'ZZ_ROOT', 1, 2, 'ZZ_ROOT/ZZ_B', '', '', 1, 'Published', '2010-01-01', '2299-12-31'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_E', 'ZZ E', 'ZZ_ROOT', 1, 2, 'ZZ_ROOT/ZZ_E', '', '', 1, 'Published', '2017-01-01', '2024-12-31'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_G', 'ZZ G', 'ZZ_ROOT', 1, 2, 'ZZ_ROOT/ZZ_G', '', '', 1, 'Published', '2013-04-01', '2020-06-03'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_EX', 'ZZ EX', 'ZZ_E', 0, 3, 'ZZ_ROOT/ZZ_E/ZZ_EX', '', '', 1, 'Published', '2017-01-01', '2024-12-31'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_EX', 'ZZ EX', 'ZZ_B', 0, 3, 'ZZ_ROOT/ZZ_B/ZZ_EX', '', '', 1, 'Published', '2025-01-01', '2299-12-31'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_GX', 'ZZ GX', 'ZZ_G', 0, 3, 'ZZ_ROOT/ZZ_G/ZZ_GX', '', '', 1, 'Published', '2013-04-01', '2020-06-03'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_AX', 'ZZ AX', 'ZZ_A', 0, 3, 'ZZ_ROOT/ZZ_A/ZZ_AX', '', '', 1, 'Published', '2010-01-01', '2299-12-31');
--
-- Actuals (row H3), entity ZZE1, one balanced voucher each: ZZ1000 cash Dr | ZZ4000 revenue Cr, business unit on
-- both lines. FY = calendar year, P6 = June (epm_staging.fiscal_periods gives each period's end_date):
--   ZZ_EX FY2018 P6 100 | ZZ_GX FY2018 P6 20 | ZZ_AX FY2024 P6 3 | ZZ_EX FY2025 P6 500 | ZZ_AX FY2025 P6 4000
-- So on ZZ1000: FY2018 ZZ_E 100, ZZ_G 20, ZZ_ROOT 120, no ZZ_B; FY2024 ZZ_A "Alpha" 3; FY2025 ZZ_B 500,
-- ZZ_A "Alpha New" 4000, ZZ_ROOT 4500, no ZZ_E or ZZ_G.
--
-- Where the dimensioned rows enter: with erp_sources = [] (the default since PR #211) the ERP GL path
-- (epm_raw.general_journal_*) is an empty relation, and a trial-balance submission carries no dimensions
-- (konsol#218), so no fixture row on either path reaches gold_trial_balance with a business unit. The rows
-- are seeded one layer up instead, in bronze_general_journal_account_entries: an incremental model, so a
-- build over an empty ERP source keeps the rows already in it (delete+insert on recid deletes nothing).
--
-- The lineage of gold_trial_balance reads these tables too, empty here, so they are named to exist:
-- epm_raw.general_journal_account_entry_bi_entities, epm_raw.general_journal_entry_bi_entities,
-- epm_raw.fiscal_calendar_years, epm_gold.entity_fiscal_calendars, epm_staging.dimension_mappings,
-- epm_raw.trial_balance_submissions, epm_raw.trial_balance_submission_control.
--
-- The live submission tables and chart may predate their partner, basis and retained-earnings columns: add them first.
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS partner_data_area_id String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
ALTER TABLE epm_staging.main_accounts ADD COLUMN IF NOT EXISTS is_retained_earnings UInt8 DEFAULT 0;
INSERT INTO epm_staging.main_accounts
  (main_account, account_name, chart_of_accounts, parent_account, is_group, account_type, statement_section, sub_section, normal_balance, time_balance, fx_method, is_posting, is_suspended, allow_ic, cf_category, cf_line_item, is_cash, main_account_category, status, is_retained_earnings)
VALUES
  ('ZZ1000', 'ZZ cash', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 1, 'CASH', 'Published', 0),
  ('ZZ4000', 'ZZ revenue', 'ZZCOA', '', 0, 'Revenue', 'Profit and Loss', 'Revenue', 'Credit', 'Period', 'average', 1, 0, 0, '', '', 0, 'REVENUE', 'Published', 0);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2018, 6, 'FY2018-P06', 'Jun 2018', 'Regular', '2018-06-01', '2018-06-30', 'Q2', 'Closed'),
  (2024, 6, 'FY2024-P06', 'Jun 2024', 'Regular', '2024-06-01', '2024-06-30', 'Q2', 'Closed'),
  (2025, 6, 'FY2025-P06', 'Jun 2025', 'Regular', '2025-06-01', '2025-06-30', 'Q2', 'Open');
-- The bronze table is a dbt model; when the live stack has none to clone, create it with the model's columns.
CREATE TABLE IF NOT EXISTS epm_bronze.bronze_general_journal_account_entries
  (recid Int64, data_area_id String, accounting_date Date, main_account String,
   accounting_currency_amount Decimal(38, 2), reporting_currency_amount Decimal(38, 2),
   transaction_currency_amount Decimal(38, 2), transaction_currency_code String, posting_type String,
   general_journal_entry_recid Int64, ledger_account String, description String, partner_data_area_id String,
   dim_business_unit String, dim_cost_center String, dim_department String,
   _airbyte_extracted_at DateTime, _airbyte_raw_id String)
  ENGINE = ReplacingMergeTree(_airbyte_extracted_at) PARTITION BY toYear(accounting_date) ORDER BY (data_area_id, accounting_date, recid);
INSERT INTO epm_bronze.bronze_general_journal_account_entries
  (recid, data_area_id, accounting_date, main_account, accounting_currency_amount, reporting_currency_amount, transaction_currency_amount, transaction_currency_code, posting_type, general_journal_entry_recid, ledger_account, description, dim_business_unit, dim_cost_center, dim_department, _airbyte_extracted_at, _airbyte_raw_id)
VALUES
  (990201, 'ZZE1', '2018-06-15', 'ZZ1000', 100, 0, 100, 'USD', 'LedgerJournal', 0, 'ZZ1000-ZZ_EX', 'ZZ cash', 'ZZ_EX', '', '', '2026-09-15 00:00:00', 'zz-h3-1'),
  (990202, 'ZZE1', '2018-06-15', 'ZZ4000', -100, 0, -100, 'USD', 'LedgerJournal', 0, 'ZZ4000-ZZ_EX', 'ZZ revenue', 'ZZ_EX', '', '', '2026-09-15 00:00:00', 'zz-h3-2'),
  (990203, 'ZZE1', '2018-06-15', 'ZZ1000', 20, 0, 20, 'USD', 'LedgerJournal', 0, 'ZZ1000-ZZ_GX', 'ZZ cash', 'ZZ_GX', '', '', '2026-09-15 00:00:00', 'zz-h3-3'),
  (990204, 'ZZE1', '2018-06-15', 'ZZ4000', -20, 0, -20, 'USD', 'LedgerJournal', 0, 'ZZ4000-ZZ_GX', 'ZZ revenue', 'ZZ_GX', '', '', '2026-09-15 00:00:00', 'zz-h3-4'),
  (990205, 'ZZE1', '2024-06-15', 'ZZ1000', 3, 0, 3, 'USD', 'LedgerJournal', 0, 'ZZ1000-ZZ_AX', 'ZZ cash', 'ZZ_AX', '', '', '2026-09-15 00:00:00', 'zz-h3-5'),
  (990206, 'ZZE1', '2024-06-15', 'ZZ4000', -3, 0, -3, 'USD', 'LedgerJournal', 0, 'ZZ4000-ZZ_AX', 'ZZ revenue', 'ZZ_AX', '', '', '2026-09-15 00:00:00', 'zz-h3-6'),
  (990207, 'ZZE1', '2025-06-15', 'ZZ1000', 500, 0, 500, 'USD', 'LedgerJournal', 0, 'ZZ1000-ZZ_EX', 'ZZ cash', 'ZZ_EX', '', '', '2026-09-15 00:00:00', 'zz-h3-7'),
  (990208, 'ZZE1', '2025-06-15', 'ZZ4000', -500, 0, -500, 'USD', 'LedgerJournal', 0, 'ZZ4000-ZZ_EX', 'ZZ revenue', 'ZZ_EX', '', '', '2026-09-15 00:00:00', 'zz-h3-8'),
  (990209, 'ZZE1', '2025-06-15', 'ZZ1000', 4000, 0, 4000, 'USD', 'LedgerJournal', 0, 'ZZ1000-ZZ_AX', 'ZZ cash', 'ZZ_AX', '', '', '2026-09-15 00:00:00', 'zz-h3-9'),
  (990210, 'ZZE1', '2025-06-15', 'ZZ4000', -4000, 0, -4000, 'USD', 'LedgerJournal', 0, 'ZZ4000-ZZ_AX', 'ZZ revenue', 'ZZ_AX', '', '', '2026-09-15 00:00:00', 'zz-h3-10');
