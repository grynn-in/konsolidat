-- konsol#117 pair 3 K2 (IFRS 11.B34-B37): an intercompany pair with a joint operation is eliminated at the operator's share.
-- Group ZZG (EUR): ZZP's own entity 100% full, joint operation ZZJ 50% proportional from 2020-01-01, both EUR (no rates).
-- ZZ1100 (receivable) <-> ZZ2100 (payable) is a Published pair of 1000 in FY2026 P1 (period movement):
--   ZZP ZZ1100 +1000 (partner ZZJ) | ZZP ZZ3000 -1000
--   ZZJ ZZ1000 +1000               | ZZJ ZZ2100 -1000 (partner ZZP)
-- The balances agree, so there is no difference leg. Layer 1 carries ZZJ at 50%, so the matched legs are 500 on each side
-- (not 1000). Unrealised profit: ZZP sells to ZZJ, ending inventory 1000, margin 20%: 200 x least(1.0, 0.5) = 100.
-- gate: build +gold_ic_eliminations assert_ic_eliminated_in_full assert_ic_full_view_nets_zero assert_unrealized_profit_at_operator_share
-- gate: expect assert_ic_eliminated_in_full pass
-- gate: expect assert_ic_full_view_nets_zero pass
-- gate: expect assert_unrealized_profit_at_operator_share pass
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
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS nci_measurement String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS accounting_framework String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS framework_note String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS goodwill_treatment String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS goodwill_amortisation_years UInt16 DEFAULT 0;
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS acquisition_costs_treatment String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS measurement_period String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS bargain_purchase String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS goodwill_account String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS fair_value_adjustment_account String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS investment_account String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS nci_account String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS bargain_purchase_gain_account String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS disposal_gain_loss_account String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS disposal_proceeds_account String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS goodwill_amortisation_expense_account String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS acquisition_costs_account String DEFAULT '';
CREATE TABLE IF NOT EXISTS epm_staging.business_combinations (name String, consolidation_group String, acquired_entity String, acquisition_date Date, share_acquired_pct Float64, consideration_currency String, total_consideration Float64, net_assets_acquired Float64, fair_value_adjustments Float64, goodwill Float64, bargain_purchase_gain Float64, nci_at_acquisition Float64, ownership_period String) ENGINE = MergeTree ORDER BY name;
ALTER TABLE epm_staging.business_combinations ADD COLUMN IF NOT EXISTS nci_measurement String DEFAULT '';
ALTER TABLE epm_staging.business_combinations ADD COLUMN IF NOT EXISTS nci_fair_value Float64 DEFAULT 0;
CREATE TABLE IF NOT EXISTS epm_staging.business_combination_consideration (parent String, idx UInt16, component String, amount Float64, currency String, settlement_date Date, description String) ENGINE = MergeTree ORDER BY (parent, idx);
CREATE TABLE IF NOT EXISTS epm_staging.business_combination_acquired_balances (parent String, idx UInt16, main_account String, book_amount Float64, fair_value_adjustment Float64, note String) ENGINE = MergeTree ORDER BY (parent, idx);
CREATE TABLE IF NOT EXISTS epm_staging.business_combination_costs (parent String, idx UInt16, kind String, amount Float64, currency String, description String) ENGINE = MergeTree ORDER BY (parent, idx);
CREATE TABLE IF NOT EXISTS epm_staging.business_disposals (name String, consolidation_group String, disposed_entity String, disposal_date Date, share_disposed_pct Float64, retained_interest_pct Float64, proceeds_currency String, total_proceeds Float64, ownership_period String) ENGINE = MergeTree ORDER BY name;
CREATE TABLE IF NOT EXISTS epm_staging.business_disposal_proceeds (parent String, idx UInt16, component String, amount Float64, currency String, settlement_date Date, description String) ENGINE = MergeTree ORDER BY (parent, idx);
-- The fully consolidated TB's other layers read these live tables, empty here: epm_staging.consolidation_adjustments,
-- epm_staging.ic_balances, epm_staging.ic_elimination_rules, epm_staging.intercompany_accounts, and the deal tables below.
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
  ('ZZ3400', 'ZZ non-controlling interest', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 0),
  ('ZZ4000', 'ZZ revenue', 'ZZCOA', '', 0, 'Revenue', 'Profit and Loss', 'Revenue', 'Credit', 'Period', 'average', 1, 0, 0, '', '', 0, 'REVENUE', 'Published', 0),
  ('ZZ5900', 'ZZ intercompany differences', 'ZZCOA', '', 0, 'Expense', 'Profit and Loss', 'Operating Expenses', 'Debit', 'Period', 'average', 1, 0, 0, '', '', 0, 'EXPENSE', 'Published', 0);
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
  ('ZZP', 'ZZ Parent', 'ZZG', 0, 'Active', 'EUR', 'DE', ''),
  ('ZZJ', 'ZZ Joint Operation', 'ZZG', 0, 'Active', 'EUR', 'DE', '');
INSERT INTO epm_gold.currencies
  (currency_code, currency_name, symbol, minor_unit)
VALUES
  ('EUR', 'Euro', 'E', 2);
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency, ic_difference_account, ic_difference_tolerance, nci_account)
VALUES
  ('ZZG', '', 'ZZ Group', 'EUR', 'ZZ5900', 0, 'ZZ3400'),
  ('ZZG', 'ZZP', 'ZZ Parent', 'EUR', '', 0, ''),
  ('ZZG', 'ZZJ', 'ZZ Joint Operation', 'EUR', '', 0, '');
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZG', 'ZZP', 'ZZG', 'ZZP', 1, 1, 'ZZG/ZZP', 'ZZG/ZZP', 'ZZG', ''),
  ('ZZG', 'ZZJ', 'ZZG', 'ZZJ', 1, 1, 'ZZG/ZZJ', 'ZZG/ZZJ', 'ZZG', '');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id)
VALUES
  ('ZZG', 'ZZP', '2026-01-01', '2149-06-06', 100, 'full', 'ZZG', ''),
  ('ZZG', 'ZZJ', '2020-01-01', '2149-06-06', 50, 'proportional', 'ZZG', '');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZBP1', 'ZZP', 2026, 1, 'ZZ1100', 1000, 0, '', 'ZZ-TBS-P1', '2026-02-05 09:00:00', 'ZZJ'),
  ('ZZBP1', 'ZZP', 2026, 1, 'ZZ3000', 0, 1000, '', 'ZZ-TBS-P1', '2026-02-05 09:00:00', ''),
  ('ZZBJ1', 'ZZJ', 2026, 1, 'ZZ1000', 1000, 0, '', 'ZZ-TBS-J1', '2026-02-05 09:00:00', ''),
  ('ZZBJ1', 'ZZJ', 2026, 1, 'ZZ2100', 0, 1000, '', 'ZZ-TBS-J1', '2026-02-05 09:00:00', 'ZZP');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZBP1', 'ZZ-TBS-P1', 'ZZP', 2026, 1, 2, '2026-02-05 09:00:00', 'Period movement'),
  ('ZZBJ1', 'ZZ-TBS-J1', 'ZZJ', 2026, 1, 2, '2026-02-05 09:00:00', 'Period movement');
INSERT INTO epm_staging.ic_elimination_rules
  (rule_id, rule_name, debit_account, credit_account, debit_entity_pattern, credit_entity_pattern, rule_type, margin_pct, asset_account)
VALUES
  ('ZZUP1', 'ZZ unrealised profit', 'ZZ4000', 'ZZ1000', 'ZZP', 'ZZJ', 'unrealized_profit', 20, 'ZZ1000');
INSERT INTO epm_staging.ic_balances
  (selling_entity, buying_entity, fiscal_year, fiscal_period, ic_sales_amount, ending_inventory_from_ic)
VALUES
  ('ZZP', 'ZZJ', 2026, 1, 1000, 1000);
