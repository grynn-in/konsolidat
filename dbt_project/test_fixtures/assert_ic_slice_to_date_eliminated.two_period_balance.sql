-- gate: build +gold_fully_consolidated_tb assert_ic_slice_to_date_eliminated assert_ic_elimination_nets_zero assert_ic_elimination_slices_sum_to_the_leg assert_ic_elimination_share_is_bounded assert_ic_slice_not_moved_past_its_own assert_end_to_end_bs_balances
-- gate: expect assert_ic_slice_to_date_eliminated pass
-- gate: expect assert_ic_elimination_nets_zero pass
-- gate: expect assert_ic_elimination_slices_sum_to_the_leg pass
-- gate: expect assert_ic_elimination_share_is_bounded pass
-- gate: expect assert_ic_slice_not_moved_past_its_own pass
-- gate: expect assert_end_to_end_bs_balances pass
-- konsolidat#245 option C, PR #260 review F1. A BALANCE-basis intercompany pair is eliminated TO DATE
-- (gold_ic_eliminations decision 14: each period posts the change in the to-date elimination), so its
-- slices must be split by each slice's TO-DATE balance, not by what the slice moved in the period.
-- Group ZZG (EUR), ZZA 100% and ZZB 100% full, both EUR. No intercompany-difference account, so every
-- ic_elimination row on these accounts is the MATCHED part. Two pairs, both receivable (A) / payable (B):
--   case (a), ZZ1100/ZZ2100, partner books a period late:
--     P1  ZZA ZZ1100 +100 on ZZ-CC1 (partner ZZB); ZZB books nothing. Matched 0, nothing eliminated.
--     P2  ZZB ZZ2100 -100 on ZZ-CC9 (partner ZZA). Matched 100 to date: A's leg is -100 and A moved 0
--         in P2. Expected: the -100 goes to ZZ-CC1, where A's balance is. On the base it went to the
--         blank slice: ZZ-CC1 kept +100 and the blank slice held -100 forever.
--   case (b), ZZ1200/ZZ2200, reclass inside A:
--     P1  ZZA ZZ1200 +100 on ZZ-CC1, ZZB ZZ2200 -100 on ZZ-CC9: eliminated in full.
--     P2  ZZA moves the receivable from ZZ-CC1 to ZZ-CC2 (-100 / +100); the IC balance does not change,
--         so the leg is 0. Expected: +100 on ZZ-CC1 and -100 on ZZ-CC2. On the base ZZ-CC1 kept an
--         elimination of -100 against a balance of 0 and ZZ-CC2's +100 was never eliminated.
-- Red on the base: assert_ic_slice_to_date_eliminated returns 4 rows (P2: ZZ1100 ZZ-CC1 and blank,
-- ZZ1200 ZZ-CC1 and ZZ-CC2).
-- Tables named so the gate creates them (empty): epm_raw.general_journal_account_entry_bi_entities,
-- epm_raw.general_journal_entry_bi_entities, epm_raw.ledgers, epm_raw.legal_entities,
-- epm_raw.fiscal_calendar_years, epm_staging.historical_equity_rates,
-- epm_staging.dimension_mappings, epm_staging.group_exchange_rates, epm_staging.ic_balances,
-- epm_staging.ic_elimination_rules, epm_staging.consolidation_adjustments.
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS dim_business_unit String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS dim_cost_center String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS dim_department String DEFAULT '';
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
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS ic_difference_account String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS ic_difference_tolerance Float64 DEFAULT 0;
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS nci_account String DEFAULT '';
INSERT INTO epm_staging.main_accounts
  (main_account, account_name, chart_of_accounts, parent_account, is_group, account_type, statement_section, sub_section, normal_balance, time_balance, fx_method, is_posting, is_suspended, allow_ic, cf_category, cf_line_item, is_cash, main_account_category, status, is_retained_earnings)
VALUES
  ('ZZ1000', 'ZZ cash', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 1, 'CASH', 'Published', 0),
  ('ZZ1100', 'ZZ intercompany receivables (a)', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 1, '', '', 0, 'RECEIVABLES', 'Published', 0),
  ('ZZ1200', 'ZZ intercompany receivables (b)', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 1, '', '', 0, 'RECEIVABLES', 'Published', 0),
  ('ZZ2100', 'ZZ intercompany payables (a)', 'ZZCOA', '', 0, 'Liability', 'Balance Sheet', 'Current Liabilities', 'Credit', 'Balance', 'closing', 1, 0, 1, '', '', 0, 'PAYABLES', 'Published', 0),
  ('ZZ2200', 'ZZ intercompany payables (b)', 'ZZCOA', '', 0, 'Liability', 'Balance Sheet', 'Current Liabilities', 'Credit', 'Balance', 'closing', 1, 0, 1, '', '', 0, 'PAYABLES', 'Published', 0),
  ('ZZ3000', 'ZZ share capital', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 0),
  ('ZZ3100', 'ZZ retained earnings', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 1),
  ('ZZ3400', 'ZZ non-controlling interest', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 0);
INSERT INTO epm_staging.intercompany_accounts
  (main_account, counterpart_account, description, status)
VALUES
  ('ZZ1100', 'ZZ2100', 'ZZ test: #260 F1 case (a)', 'Published'),
  ('ZZ1200', 'ZZ2200', 'ZZ test: #260 F1 case (b)', 'Published');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open'),
  (2026, 2, 'FY2026-P02', 'Feb 2026', 'Regular', '2026-02-01', '2026-02-28', 'Q1', 'Open'),
  (2026, 13, 'FY2026-P13', 'FY2026 closing', 'Closing', '2026-12-31', '2026-12-31', 'Q4', 'Open');
INSERT INTO epm_staging.entities
  (data_area_id, entity_name, parent_entity, is_group, status, accounting_currency, country, erp_source)
VALUES
  ('ZZA', 'ZZ Parent', 'ZZG', 0, 'Active', 'EUR', 'DE', ''),
  ('ZZB', 'ZZ Subsidiary', 'ZZG', 0, 'Active', 'EUR', 'DE', '');
INSERT INTO epm_gold.currencies
  (currency_code, currency_name, symbol, minor_unit)
VALUES
  ('EUR', 'Euro', 'E', 2);
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency, ic_difference_account, ic_difference_tolerance, nci_account)
VALUES
  ('ZZG', '', 'ZZ Group', 'EUR', '', 0, 'ZZ3400'),
  ('ZZG', 'ZZA', 'ZZ Parent', 'EUR', '', 0, ''),
  ('ZZG', 'ZZB', 'ZZ Subsidiary', 'EUR', '', 0, '');
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZG', 'ZZA', 'ZZG', 'ZZA', 1, 1, 'ZZG/ZZA', 'ZZG/ZZA', 'ZZG', ''),
  ('ZZG', 'ZZB', 'ZZG', 'ZZB', 1, 1, 'ZZG/ZZB', 'ZZG/ZZB', 'ZZG', '');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id)
VALUES
  ('ZZG', 'ZZA', '2026-01-01', '2149-06-06', 100, 'full', 'ZZG', ''),
  ('ZZG', 'ZZB', '2026-01-01', '2149-06-06', 100, 'full', 'ZZG', '');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id, dim_cost_center)
VALUES
  ('ZZBA1', 'ZZA', 2026, 1, 'ZZ1100', 100, 0, '', 'ZZ-TBS-A1', '2026-02-05 09:00:00', 'ZZB', 'ZZ-CC1'),
  ('ZZBA1', 'ZZA', 2026, 1, 'ZZ1200', 100, 0, '', 'ZZ-TBS-A1', '2026-02-05 09:00:00', 'ZZB', 'ZZ-CC1'),
  ('ZZBA1', 'ZZA', 2026, 1, 'ZZ3000', 0, 200, '', 'ZZ-TBS-A1', '2026-02-05 09:00:00', '', ''),
  ('ZZBB1', 'ZZB', 2026, 1, 'ZZ1000', 100, 0, '', 'ZZ-TBS-B1', '2026-02-05 09:00:00', '', ''),
  ('ZZBB1', 'ZZB', 2026, 1, 'ZZ2200', 0, 100, '', 'ZZ-TBS-B1', '2026-02-05 09:00:00', 'ZZA', 'ZZ-CC9'),
  ('ZZBA2', 'ZZA', 2026, 2, 'ZZ1200', 0, 100, '', 'ZZ-TBS-A2', '2026-03-05 09:00:00', 'ZZB', 'ZZ-CC1'),
  ('ZZBA2', 'ZZA', 2026, 2, 'ZZ1200', 100, 0, '', 'ZZ-TBS-A2', '2026-03-05 09:00:00', 'ZZB', 'ZZ-CC2'),
  ('ZZBB2', 'ZZB', 2026, 2, 'ZZ1000', 100, 0, '', 'ZZ-TBS-B2', '2026-03-05 09:00:00', '', ''),
  ('ZZBB2', 'ZZB', 2026, 2, 'ZZ2100', 0, 100, '', 'ZZ-TBS-B2', '2026-03-05 09:00:00', 'ZZA', 'ZZ-CC9');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZBA1', 'ZZ-TBS-A1', 'ZZA', 2026, 1, 3, '2026-02-05 09:00:00', 'Period movement'),
  ('ZZBB1', 'ZZ-TBS-B1', 'ZZB', 2026, 1, 2, '2026-02-05 09:00:00', 'Period movement'),
  ('ZZBA2', 'ZZ-TBS-A2', 'ZZA', 2026, 2, 2, '2026-03-05 09:00:00', 'Period movement'),
  ('ZZBB2', 'ZZ-TBS-B2', 'ZZB', 2026, 2, 2, '2026-03-05 09:00:00', 'Period movement');
-- konsol#348 S4-Q7 (a): the one Rate Set flagged Is Actuals; the consolidation guard refuses a build with zero flagged sets even when nothing is translated.
INSERT INTO epm_staging.rate_sets
  (rate_set, label, is_actuals)
VALUES
  ('ZZACT', 'ZZ actuals', 1);
