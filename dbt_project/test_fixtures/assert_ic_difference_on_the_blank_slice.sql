-- gate: build +gold_fully_consolidated_tb assert_ic_difference_on_the_blank_slice assert_ic_elimination_nets_zero assert_ic_elimination_slices_sum_to_the_leg
-- gate: expect assert_ic_difference_on_the_blank_slice pass
-- gate: expect assert_ic_elimination_nets_zero pass
-- gate: expect assert_ic_elimination_slices_sum_to_the_leg pass
-- konsolidat#245 Q1 A (Deepak Pai, 21 Nov 2026): the intercompany DIFFERENCE entry is posted on the blank
-- slice on both legs, the IC-account leg included; only the matched part carries the side's slices.
-- Group ZZG (EUR), ZZA and ZZB 100% full, both EUR, one period. The group declares an intercompany-
-- difference account (ZZ1900, tolerance 0), so each pair below books a difference of 10. Two pairs:
--   balance pair ZZ1100/ZZ2100: ZZA receivable +100 (ZZ-CC1 +60, ZZ-CC2 +40, partner ZZB); ZZB payable
--     -90 on ZZ-CC9. Matched 90: ZZ-CC1 -54, ZZ-CC2 -36, ZZ-CC9 +90. Difference 10: -10 on ZZ1100 and
--     +10 on ZZ1900, both on the BLANK slice.
--   movement pair ZZ4100/ZZ5100: ZZA intercompany revenue -100 (ZZ-CC1 -60, ZZ-CC2 -40, partner ZZB);
--     ZZB intercompany expense +90 on ZZ-CC9. Matched 90: ZZ-CC1 +54, ZZ-CC2 +36, ZZ-CC9 -90. Difference
--     10: +10 on ZZ4100 and -10 on ZZ1900, both on the BLANK slice.
-- Red on the base (fc7cbf4 merged with main): layer 2 split each IC-account difference leg by the side's
-- slices (ZZ1100 ZZ-CC1 -6 / ZZ-CC2 -4, ZZ4100 ZZ-CC1 +6 / ZZ-CC2 +4), so the sliced figure on each IC
-- account is 100 against a matched allowance of 90: assert_ic_difference_on_the_blank_slice returns 2 rows
-- (ZZ1100 and ZZ4100, 2026 P1). Green: 0 rows. The two total-based checks pass at both shas: the
-- difference moves between slices, not between accounts.
-- Tables named so the gate creates them (empty): epm_raw.general_journal_account_entry_bi_entities,
-- epm_raw.general_journal_entry_bi_entities, epm_raw.ledgers, epm_raw.legal_entities,
-- epm_raw.fiscal_calendar_years, epm_gold.entity_fiscal_calendars, epm_staging.historical_equity_rates,
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
  ('ZZ1100', 'ZZ intercompany receivables', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 1, '', '', 0, 'RECEIVABLES', 'Published', 0),
  ('ZZ1900', 'ZZ intercompany differences', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 0, 'RECEIVABLES', 'Published', 0),
  ('ZZ2100', 'ZZ intercompany payables', 'ZZCOA', '', 0, 'Liability', 'Balance Sheet', 'Current Liabilities', 'Credit', 'Balance', 'closing', 1, 0, 1, '', '', 0, 'PAYABLES', 'Published', 0),
  ('ZZ3000', 'ZZ share capital', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 0),
  ('ZZ3100', 'ZZ retained earnings', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 1),
  ('ZZ3400', 'ZZ non-controlling interest', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 0),
  ('ZZ4100', 'ZZ intercompany revenue', 'ZZCOA', '', 0, 'Revenue', 'Profit and Loss', 'Revenue', 'Credit', 'Period', 'average', 1, 0, 1, '', '', 0, 'REVENUE', 'Published', 0),
  ('ZZ5100', 'ZZ intercompany expense', 'ZZCOA', '', 0, 'Expense', 'Profit and Loss', 'Operating expenses', 'Debit', 'Period', 'average', 1, 0, 1, '', '', 0, 'OPEX', 'Published', 0);
INSERT INTO epm_staging.intercompany_accounts
  (main_account, counterpart_account, description, status)
VALUES
  ('ZZ1100', 'ZZ2100', 'ZZ test: #245 Q1 balance pair', 'Published'),
  ('ZZ4100', 'ZZ5100', 'ZZ test: #245 Q1 movement pair', 'Published');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open'),
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
  ('ZZG', '', 'ZZ Group', 'EUR', 'ZZ1900', 0, 'ZZ3400'),
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
  ('ZZBA1', 'ZZA', 2026, 1, 'ZZ1100', 60, 0, '', 'ZZ-TBS-A1', '2026-02-05 09:00:00', 'ZZB', 'ZZ-CC1'),
  ('ZZBA1', 'ZZA', 2026, 1, 'ZZ1100', 40, 0, '', 'ZZ-TBS-A1', '2026-02-05 09:00:00', 'ZZB', 'ZZ-CC2'),
  ('ZZBA1', 'ZZA', 2026, 1, 'ZZ4100', 0, 60, '', 'ZZ-TBS-A1', '2026-02-05 09:00:00', 'ZZB', 'ZZ-CC1'),
  ('ZZBA1', 'ZZA', 2026, 1, 'ZZ4100', 0, 40, '', 'ZZ-TBS-A1', '2026-02-05 09:00:00', 'ZZB', 'ZZ-CC2'),
  ('ZZBA1', 'ZZA', 2026, 1, 'ZZ3000', 0, 100, '', 'ZZ-TBS-A1', '2026-02-05 09:00:00', '', ''),
  ('ZZBA1', 'ZZA', 2026, 1, 'ZZ1000', 100, 0, '', 'ZZ-TBS-A1', '2026-02-05 09:00:00', '', ''),
  ('ZZBB1', 'ZZB', 2026, 1, 'ZZ1000', 90, 0, '', 'ZZ-TBS-B1', '2026-02-05 09:00:00', '', ''),
  ('ZZBB1', 'ZZB', 2026, 1, 'ZZ2100', 0, 90, '', 'ZZ-TBS-B1', '2026-02-05 09:00:00', 'ZZA', 'ZZ-CC9'),
  ('ZZBB1', 'ZZB', 2026, 1, 'ZZ5100', 90, 0, '', 'ZZ-TBS-B1', '2026-02-05 09:00:00', 'ZZA', 'ZZ-CC9'),
  ('ZZBB1', 'ZZB', 2026, 1, 'ZZ1000', 0, 90, '', 'ZZ-TBS-B1', '2026-02-05 09:00:00', '', '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZBA1', 'ZZ-TBS-A1', 'ZZA', 2026, 1, 6, '2026-02-05 09:00:00', 'Period movement'),
  ('ZZBB1', 'ZZ-TBS-B1', 'ZZB', 2026, 1, 4, '2026-02-05 09:00:00', 'Period movement');
-- konsol#348 S4-Q7 (a): the one Rate Set flagged Is Actuals; the consolidation guard refuses a build with zero flagged sets even when nothing is translated.
INSERT INTO epm_staging.rate_sets
  (rate_set, label, is_actuals)
VALUES
  ('ZZACT', 'ZZ actuals', 1);
