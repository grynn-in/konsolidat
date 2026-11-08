-- konsol#117 pair 2 K3: a group with a full-method entity held below 100% must declare nci_account on its root
-- (the NCI line K2 posts and the deal journals use). Replaces ic_nci_account_declared (konsolidat#208).
-- Group ZZG (USD): ZZP held 100%, ZZS held 80%, both full from 2026-01-01, both USD (no rates).
-- The root row declares ZZ3400: nothing is flagged.
-- gate: build +gold_entity_ownership assert_nci_account_declared_for_partial_subs
-- gate: expect assert_nci_account_declared_for_partial_subs pass
-- The live consolidation_groups may predate its IC and policy columns, and the submission tables their partner
-- and basis columns: add them first. The lineage of gold_consolidated_trial_balance reads these tables too, empty
-- here, so they are named to exist (empty): epm_raw.general_journal_account_entry_bi_entities,
-- epm_raw.general_journal_entry_bi_entities, epm_raw.ledgers, epm_raw.legal_entities,
-- epm_raw.fiscal_calendar_years, epm_gold.entity_fiscal_calendars, epm_staging.historical_equity_rates,
-- epm_staging.dimension_mappings, epm_staging.group_exchange_rates, epm_staging.ic_balances,
-- epm_staging.ic_elimination_rules.
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS partner_data_area_id String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
ALTER TABLE epm_staging.consolidation_ancestry ADD COLUMN IF NOT EXISTS path_id String, ADD COLUMN IF NOT EXISTS link_owner_group String, ADD COLUMN IF NOT EXISTS link_owner_data_area_id String;
ALTER TABLE epm_staging.ownership_periods ADD COLUMN IF NOT EXISTS owner_group String, ADD COLUMN IF NOT EXISTS owner_data_area_id String, MODIFY ORDER BY (consolidation_group, data_area_id, effective_date, owner_group, owner_data_area_id);
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
  ('ZZ3000', 'ZZ share capital', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 0),
  ('ZZ3100', 'ZZ retained earnings', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 1),
  ('ZZ3400', 'ZZ non-controlling interest', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 0);
INSERT INTO epm_staging.intercompany_accounts
  (main_account, counterpart_account, description, status)
VALUES
  ('ZZ1100', 'ZZ2100', 'ZZ test: konsolidat#208', 'Published');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open'),
  (2026, 13, 'FY2026-P13', 'FY2026 closing', 'Closing', '2026-12-31', '2026-12-31', 'Q4', 'Open');
INSERT INTO epm_staging.entities
  (data_area_id, entity_name, parent_entity, is_group, status, accounting_currency, country, erp_source)
VALUES
  ('ZZP', 'ZZ Parent', 'ZZG', 0, 'Active', 'USD', 'US', ''),
  ('ZZS', 'ZZ Subsidiary', 'ZZG', 0, 'Active', 'USD', 'US', '');
INSERT INTO epm_gold.currencies
  (currency_code, currency_name, symbol, minor_unit)
VALUES
  ('USD', 'US Dollar', '$', 2);
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency, ic_difference_account, ic_difference_tolerance, nci_account)
VALUES
  ('ZZG', '', 'ZZ Group', 'USD', '', 0, 'ZZ3400'),
  ('ZZG', 'ZZP', 'ZZ Parent', 'USD', '', 0, ''),
  ('ZZG', 'ZZS', 'ZZ Subsidiary', 'USD', '', 0, '');
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZG', 'ZZP', 'ZZG', 'ZZP', 1, 1, 'ZZG/ZZP', 'ZZG/ZZP', 'ZZG', ''),
  ('ZZG', 'ZZS', 'ZZG', 'ZZS', 1, 1, 'ZZG/ZZS', 'ZZG/ZZS', 'ZZG', '');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id)
VALUES
  ('ZZG', 'ZZP', '2026-01-01', '2149-06-06', 100, 'full', 'ZZG', ''),
  ('ZZG', 'ZZS', '2026-01-01', '2149-06-06', 80, 'full', 'ZZG', '');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZBP1', 'ZZP', 2026, 1, 'ZZ1100', 1000, 0, '', 'ZZ-TBS-P1', '2026-02-05 09:00:00', 'ZZS'),
  ('ZZBP1', 'ZZP', 2026, 1, 'ZZ3000', 0, 1000, '', 'ZZ-TBS-P1', '2026-02-05 09:00:00', ''),
  ('ZZBS1', 'ZZS', 2026, 1, 'ZZ1000', 1000, 0, '', 'ZZ-TBS-S1', '2026-02-05 09:00:00', ''),
  ('ZZBS1', 'ZZS', 2026, 1, 'ZZ2100', 0, 1000, '', 'ZZ-TBS-S1', '2026-02-05 09:00:00', 'ZZP');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZBP1', 'ZZ-TBS-P1', 'ZZP', 2026, 1, 2, '2026-02-05 09:00:00', 'Period movement'),
  ('ZZBS1', 'ZZ-TBS-S1', 'ZZS', 2026, 1, 2, '2026-02-05 09:00:00', 'Period movement');
