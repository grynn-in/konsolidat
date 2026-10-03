-- konsol#305-W3-5 (Deepak Pai, 3 Oct 2026, option C): how gold_ic_reconciliation judges each kind of pair.
-- `+assert_ic_match_status_cases +assert_ic_difference_cause` must BUILD and PASS on these rows.
--
-- Group ZZIC (USD, tolerance 10): ZZP and ZZS (USD), ZZE and ZZF (EUR), each held 100% full from 2026-01-01.
-- EUR->USD FY2026 P1: Closing 1.20, Average 1.15. Published pairs ZZ1100 <-> ZZ2100 (balance sheet) and
-- ZZ4100 <-> ZZ5100 (P&L). FY2026 P1, period movement:
--   ZZP ZZ1100 +1000 (partner ZZE) | ZZE ZZ2100 -800 EUR = -960 USD (partner ZZP): balance, USD/EUR, difference 40
--   ZZS ZZ1100 +1000 (partner ZZF) | ZZF ZZ2100 -830 EUR = -996 USD (partner ZZS): balance, USD/EUR, difference 4
--   ZZP ZZ4100 -1000 (partner ZZE) | ZZE ZZ5100 +800 EUR = +920 USD (partner ZZP): movement, USD/EUR, difference -80
--   ZZP ZZ1100 +1000 (partner ZZS) | ZZS ZZ2100 -950 (partner ZZP):                 balance, USD/USD, difference 50
-- Offsets on cash ZZ1000 keep every trial balance balanced.
--
-- The live consolidation_groups may predate its IC and policy columns, and the submission tables their partner
-- and basis columns: add them first. The lineage of gold_consolidated_trial_balance reads these tables too, empty
-- here, so they are named to exist (empty): epm_raw.general_journal_account_entry_bi_entities,
-- epm_raw.general_journal_entry_bi_entities, epm_raw.ledgers, epm_raw.legal_entities,
-- epm_raw.fiscal_calendar_years, epm_gold.entity_fiscal_calendars, epm_staging.historical_equity_rates,
-- epm_staging.dimension_mappings, epm_staging.ic_balances, epm_staging.ic_elimination_rules.
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS partner_data_area_id String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
ALTER TABLE epm_staging.main_accounts ADD COLUMN IF NOT EXISTS is_retained_earnings UInt8 DEFAULT 0;
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS ic_difference_account String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS ic_difference_tolerance Float64 DEFAULT 0;
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS nci_account String DEFAULT '';
INSERT INTO epm_staging.main_accounts
  (main_account, account_name, chart_of_accounts, parent_account, is_group, account_type, statement_section, sub_section, normal_balance, time_balance, fx_method, is_posting, is_suspended, allow_ic, cf_category, cf_line_item, is_cash, main_account_category, status, is_retained_earnings)
VALUES
  ('ZZ1000', 'ZZ cash', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 1, 'CASH', 'Published', 0),
  ('ZZ1100', 'ZZ intercompany receivables', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 1, '', '', 0, 'RECEIVABLES', 'Published', 0),
  ('ZZ2100', 'ZZ intercompany payables', 'ZZCOA', '', 0, 'Liability', 'Balance Sheet', 'Current Liabilities', 'Credit', 'Balance', 'closing', 1, 0, 1, '', '', 0, 'PAYABLES', 'Published', 0),
  ('ZZ3100', 'ZZ retained earnings', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 1),
  ('ZZ4100', 'ZZ intercompany revenue', 'ZZCOA', '', 0, 'Revenue', 'Profit and Loss', 'Revenue', 'Credit', 'Period', 'average', 1, 0, 1, '', '', 0, 'REVENUE', 'Published', 0),
  ('ZZ5100', 'ZZ intercompany cost', 'ZZCOA', '', 0, 'Expense', 'Profit and Loss', 'Cost of Sales', 'Debit', 'Period', 'average', 1, 0, 1, '', '', 0, 'COGS', 'Published', 0);
INSERT INTO epm_staging.intercompany_accounts
  (main_account, counterpart_account, description, status)
VALUES
  ('ZZ1100', 'ZZ2100', 'ZZ test: konsol#305-W3-5 balance', 'Published'),
  ('ZZ4100', 'ZZ5100', 'ZZ test: konsol#305-W3-5 movement', 'Published');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open'),
  (2026, 13, 'FY2026-P13', 'FY2026 closing', 'Closing', '2026-12-31', '2026-12-31', 'Q4', 'Open');
INSERT INTO epm_staging.entities
  (data_area_id, entity_name, parent_entity, is_group, status, accounting_currency, country, erp_source)
VALUES
  ('ZZP', 'ZZ Parent', 'ZZIC', 0, 'Active', 'USD', 'US', ''),
  ('ZZS', 'ZZ Sub USD', 'ZZIC', 0, 'Active', 'USD', 'US', ''),
  ('ZZE', 'ZZ Sub EUR one', 'ZZIC', 0, 'Active', 'EUR', 'DE', ''),
  ('ZZF', 'ZZ Sub EUR two', 'ZZIC', 0, 'Active', 'EUR', 'DE', '');
INSERT INTO epm_gold.currencies
  (currency_code, currency_name, symbol, minor_unit, usd_log10)
VALUES
  ('EUR', 'Euro', 'E', 2, -0.05),
  ('USD', 'US Dollar', '$', 2, 0);
INSERT INTO epm_staging.group_exchange_rates
  (to_currency, from_currency, fiscal_year, fiscal_period, rate_type, rate, document)
VALUES
  ('USD', 'EUR', 2026, 1, 'Closing', 1.20, 'ZZ-GER-2026-01'),
  ('USD', 'EUR', 2026, 1, 'Average', 1.15, 'ZZ-GER-2026-01');
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency, ic_difference_account, ic_difference_tolerance, nci_account)
VALUES
  ('ZZIC', '', 'ZZ IC Group', 'USD', '', 10, ''),
  ('ZZIC', 'ZZP', 'ZZ Parent', 'USD', '', 0, ''),
  ('ZZIC', 'ZZS', 'ZZ Sub USD', 'USD', '', 0, ''),
  ('ZZIC', 'ZZE', 'ZZ Sub EUR one', 'USD', '', 0, ''),
  ('ZZIC', 'ZZF', 'ZZ Sub EUR two', 'USD', '', 0, '');
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path)
VALUES
  ('ZZIC', 'ZZP', 'ZZIC', 'ZZP', 1, 1, 'ZZIC/ZZP'),
  ('ZZIC', 'ZZS', 'ZZIC', 'ZZS', 1, 1, 'ZZIC/ZZS'),
  ('ZZIC', 'ZZE', 'ZZIC', 'ZZE', 1, 1, 'ZZIC/ZZE'),
  ('ZZIC', 'ZZF', 'ZZIC', 'ZZF', 1, 1, 'ZZIC/ZZF');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, ownership_pct, consolidation_method)
VALUES
  ('ZZIC', 'ZZP', '2026-01-01', 100, 'full'),
  ('ZZIC', 'ZZS', '2026-01-01', 100, 'full'),
  ('ZZIC', 'ZZE', '2026-01-01', 100, 'full'),
  ('ZZIC', 'ZZF', '2026-01-01', 100, 'full');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZBP1', 'ZZP', 2026, 1, 'ZZ1100', 1000, 0, '', 'ZZ-TBS-P1', '2026-02-05 09:00:00', 'ZZE'),
  ('ZZBP1', 'ZZP', 2026, 1, 'ZZ1100', 1000, 0, '', 'ZZ-TBS-P1', '2026-02-05 09:00:00', 'ZZS'),
  ('ZZBP1', 'ZZP', 2026, 1, 'ZZ4100', 0, 1000, '', 'ZZ-TBS-P1', '2026-02-05 09:00:00', 'ZZE'),
  ('ZZBP1', 'ZZP', 2026, 1, 'ZZ1000', 0, 1000, '', 'ZZ-TBS-P1', '2026-02-05 09:00:00', ''),
  ('ZZBS1', 'ZZS', 2026, 1, 'ZZ1100', 1000, 0, '', 'ZZ-TBS-S1', '2026-02-05 09:00:00', 'ZZF'),
  ('ZZBS1', 'ZZS', 2026, 1, 'ZZ2100', 0, 950, '', 'ZZ-TBS-S1', '2026-02-05 09:00:00', 'ZZP'),
  ('ZZBS1', 'ZZS', 2026, 1, 'ZZ1000', 0, 50, '', 'ZZ-TBS-S1', '2026-02-05 09:00:00', ''),
  ('ZZBE1', 'ZZE', 2026, 1, 'ZZ2100', 0, 800, '', 'ZZ-TBS-E1', '2026-02-05 09:00:00', 'ZZP'),
  ('ZZBE1', 'ZZE', 2026, 1, 'ZZ5100', 800, 0, '', 'ZZ-TBS-E1', '2026-02-05 09:00:00', 'ZZP'),
  ('ZZBF1', 'ZZF', 2026, 1, 'ZZ2100', 0, 830, '', 'ZZ-TBS-F1', '2026-02-05 09:00:00', 'ZZS'),
  ('ZZBF1', 'ZZF', 2026, 1, 'ZZ1000', 830, 0, '', 'ZZ-TBS-F1', '2026-02-05 09:00:00', '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZBP1', 'ZZ-TBS-P1', 'ZZP', 2026, 1, 4, '2026-02-05 09:00:00', 'Period movement'),
  ('ZZBS1', 'ZZ-TBS-S1', 'ZZS', 2026, 1, 3, '2026-02-05 09:00:00', 'Period movement'),
  ('ZZBE1', 'ZZ-TBS-E1', 'ZZE', 2026, 1, 2, '2026-02-05 09:00:00', 'Period movement'),
  ('ZZBF1', 'ZZ-TBS-F1', 'ZZF', 2026, 1, 2, '2026-02-05 09:00:00', 'Period movement');
