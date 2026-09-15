-- Must-flag fixture for assert_acquisition_measured_in_period (konsolidat#198 row J7, design §3):
-- `+gold_business_combination_journal assert_acquisition_measured_in_period` must BUILD and the test must
-- WARN with `Got 1 result` on these rows.
--
-- business_combination_100pct.sql's group and deal, but konsol recorded NO acquired balance sheet: the
-- business_combination_acquired_balances table is empty and the header's net_assets_acquired is 0, so the
-- net assets can only be measured from the entity's trial balance (design §3, the third precedence). Entity
-- ZZS (acquired 2026-03-15, FY2026 P3) uploaded its first trial balance for FY2026 P5 (period-end balances:
-- ZZ1100 200 Dr | ZZ1420 600 Dr | ZZ2100 150 Cr | ZZ3000 100 Cr | ZZ3100 550 Cr), two periods after the
-- acquisition, so a measurement there carries two months of post-acquisition results into the acquired
-- equity. The test names the deal with its acquisition period (2026, 3) and the first measurable period
-- (2026, 5).
-- Side effect on this fixture: gold_business_combination_journal posts nothing for a deal it cannot measure,
-- so assert_goodwill_calculated also FAILs here (Got 1 result), as its header says: the intended state of a
-- deal konsol has not finished.
--
-- The six deal tables do not exist live yet: the fixture creates the six the three journals read (the costs,
-- disposals and disposal-proceeds tables are empty here: no acquisition costs and no disposal on this deal) with
-- konsol's exact DDL (clickhouse/init-db.sql, pinned by tests/test_deal_tables_ddl.py). The live consolidation_groups,
-- main_accounts and submission control may predate their policy/flag/basis columns: add them first. The disposal
-- journal's lineage (gold_consolidated_trial_balance, gold_fx_revaluation) reads the hierarchy, ancestry, ownership
-- and currency rows of the group, so they are here too.
-- The journal reads gold_trial_balance (pre-acquisition history), whose lineage reads these tables, empty on a
-- trial-balance-only site with no upload, so they are named here to exist (empty): epm_raw.trial_balance_submissions,
-- epm_raw.trial_balance_submission_control, epm_raw.general_journal_account_entry_bi_entities,
-- epm_raw.general_journal_entry_bi_entities, epm_raw.ledgers, epm_raw.legal_entities,
-- epm_raw.fiscal_calendar_years, epm_gold.entity_fiscal_calendars, epm_staging.historical_equity_rates,
-- epm_staging.dimension_mappings.
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
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
CREATE TABLE IF NOT EXISTS epm_staging.business_combination_consideration (parent String, idx UInt16, component String, amount Float64, currency String, settlement_date Date, description String) ENGINE = MergeTree ORDER BY (parent, idx);
CREATE TABLE IF NOT EXISTS epm_staging.business_combination_acquired_balances (parent String, idx UInt16, main_account String, book_amount Float64, fair_value_adjustment Float64, note String) ENGINE = MergeTree ORDER BY (parent, idx);
CREATE TABLE IF NOT EXISTS epm_staging.business_combination_costs (parent String, idx UInt16, kind String, amount Float64, currency String, description String) ENGINE = MergeTree ORDER BY (parent, idx);
CREATE TABLE IF NOT EXISTS epm_staging.business_disposals (name String, consolidation_group String, disposed_entity String, disposal_date Date, share_disposed_pct Float64, retained_interest_pct Float64, proceeds_currency String, total_proceeds Float64, ownership_period String) ENGINE = MergeTree ORDER BY name;
CREATE TABLE IF NOT EXISTS epm_staging.business_disposal_proceeds (parent String, idx UInt16, component String, amount Float64, currency String, settlement_date Date, description String) ENGINE = MergeTree ORDER BY (parent, idx);
INSERT INTO epm_staging.main_accounts
  (main_account, account_name, chart_of_accounts, parent_account, is_group, account_type, statement_section, sub_section, normal_balance, time_balance, fx_method, is_posting, is_suspended, allow_ic, cf_category, cf_line_item, is_cash, main_account_category, status, is_retained_earnings)
VALUES
  ('ZZ1000', 'ZZ cash', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 1, 'CASH', 'Published', 0),
  ('ZZ1100', 'ZZ receivables', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 0, 'RECEIVABLES', 'Published', 0),
  ('ZZ1420', 'ZZ plant', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Non-current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 0, 'PPE', 'Published', 0),
  ('ZZ1800', 'ZZ goodwill', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Non-current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 0, 'INTANGIBLES', 'Published', 0),
  ('ZZ1900', 'ZZ fair value adjustments', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Non-current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 0, 'PPE', 'Published', 0),
  ('ZZ2100', 'ZZ payables', 'ZZCOA', '', 0, 'Liability', 'Balance Sheet', 'Current Liabilities', 'Credit', 'Balance', 'closing', 1, 0, 0, '', '', 0, 'PAYABLES', 'Published', 0),
  ('ZZ3000', 'ZZ share capital', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 0),
  ('ZZ3100', 'ZZ retained earnings', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 1),
  ('ZZ3400', 'ZZ non-controlling interest', 'ZZCOA', '', 0, 'Equity', 'Balance Sheet', 'Equity', 'Credit', 'Balance', 'historical', 1, 0, 0, '', '', 0, 'EQUITY', 'Published', 0),
  ('ZZ3500', 'ZZ investment in subsidiaries', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Non-current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 0, 'INVESTMENTS', 'Published', 0),
  ('ZZ4900', 'ZZ bargain purchase gain', 'ZZCOA', '', 0, 'Revenue', 'Profit and Loss', 'Other income', 'Credit', 'Period', 'average', 1, 0, 0, '', '', 0, 'OTHER_INCOME', 'Published', 0),
  ('ZZ4950', 'ZZ gain or loss on disposal', 'ZZCOA', '', 0, 'Revenue', 'Profit and Loss', 'Other income', 'Credit', 'Period', 'average', 1, 0, 0, '', '', 0, 'OTHER_INCOME', 'Published', 0),
  ('ZZ6900', 'ZZ goodwill amortisation', 'ZZCOA', '', 0, 'Expense', 'Profit and Loss', 'Operating expenses', 'Debit', 'Period', 'average', 1, 0, 0, '', '', 0, 'OPEX', 'Published', 0),
  ('ZZ6950', 'ZZ acquisition costs', 'ZZCOA', '', 0, 'Expense', 'Profit and Loss', 'Operating expenses', 'Debit', 'Period', 'average', 1, 0, 0, '', '', 0, 'OPEX', 'Published', 0);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open'),
  (2026, 2, 'FY2026-P02', 'Feb 2026', 'Regular', '2026-02-01', '2026-02-28', 'Q1', 'Open'),
  (2026, 3, 'FY2026-P03', 'Mar 2026', 'Regular', '2026-03-01', '2026-03-31', 'Q1', 'Open'),
  (2026, 4, 'FY2026-P04', 'Apr 2026', 'Regular', '2026-04-01', '2026-04-30', 'Q2', 'Open'),
  (2026, 5, 'FY2026-P05', 'May 2026', 'Regular', '2026-05-01', '2026-05-31', 'Q2', 'Open'),
  (2026, 6, 'FY2026-P06', 'Jun 2026', 'Regular', '2026-06-01', '2026-06-30', 'Q2', 'Open'),
  (2026, 7, 'FY2026-P07', 'Jul 2026', 'Regular', '2026-07-01', '2026-07-31', 'Q3', 'Open'),
  (2026, 8, 'FY2026-P08', 'Aug 2026', 'Regular', '2026-08-01', '2026-08-31', 'Q3', 'Open'),
  (2026, 9, 'FY2026-P09', 'Sep 2026', 'Regular', '2026-09-01', '2026-09-30', 'Q3', 'Open'),
  (2026, 10, 'FY2026-P10', 'Oct 2026', 'Regular', '2026-10-01', '2026-10-31', 'Q4', 'Open'),
  (2026, 11, 'FY2026-P11', 'Nov 2026', 'Regular', '2026-11-01', '2026-11-30', 'Q4', 'Open'),
  (2026, 12, 'FY2026-P12', 'Dec 2026', 'Regular', '2026-12-01', '2026-12-31', 'Q4', 'Open'),
  (2026, 13, 'FY2026-P13', 'FY2026 closing', 'Closing', '2026-12-31', '2026-12-31', 'Q4', 'Open');
INSERT INTO epm_staging.entities
  (data_area_id, entity_name, parent_entity, is_group, status, accounting_currency, country, erp_source)
VALUES
  ('ZZS', 'ZZ Subsidiary', 'ZZG', 0, 'Active', 'EUR', 'DE', '');
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency,
   nci_measurement, accounting_framework, goodwill_treatment, acquisition_costs_treatment, measurement_period, bargain_purchase,
   goodwill_account, fair_value_adjustment_account, investment_account, nci_account, bargain_purchase_gain_account,
   disposal_gain_loss_account, disposal_proceeds_account, goodwill_amortisation_expense_account, acquisition_costs_account)
VALUES
  ('ZZG', '', 'ZZ Group', 'USD',
   'partial', 'IFRS', 'Impairment only', 'Expense', 'Off', 'Recognise gain',
   'ZZ1800', 'ZZ1900', 'ZZ3500', 'ZZ3400', 'ZZ4900',
   'ZZ4950', 'ZZ1000', 'ZZ6900', 'ZZ6950'),
  ('ZZG', 'ZZS', 'ZZ Subsidiary', 'USD',
   '', '', '', '', '', '',
   '', '', '', '', '',
   '', '', '', '');
INSERT INTO epm_staging.consolidation_hierarchy
  (consolidation_group, data_area_id, parent_group, hierarchy_level, path)
VALUES
  ('ZZG', 'ZZS', '', 1, 'ZZG');
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path)
VALUES
  ('ZZG', 'ZZS', 'ZZG', 'ZZS', 1, 1, 'ZZG/ZZS');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, ownership_pct, consolidation_method)
VALUES
  ('ZZG', 'ZZS', '2026-03-15', 100, 'full');
INSERT INTO epm_gold.currencies
  (currency_code, currency_name, symbol, minor_unit)
VALUES
  ('EUR', 'Euro', 'E', 2),
  ('USD', 'US Dollar', '$', 2);
INSERT INTO epm_staging.group_exchange_rates
  (to_currency, from_currency, fiscal_year, fiscal_period, rate_type, rate, document)
VALUES
  ('USD', 'EUR', 2026, 3, 'Closing', 1.0, 'ZZ-GER-2026-03'),
  ('USD', 'EUR', 2026, 3, 'Average', 1.0, 'ZZ-GER-2026-03');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZM1', 'ZZS', 2026, 5, 'ZZ1100', 200, 0, 'Receivables', 'ZZ-TBS-M1', now(), ''),
  ('ZZM1', 'ZZS', 2026, 5, 'ZZ1420', 600, 0, 'Plant', 'ZZ-TBS-M1', now(), ''),
  ('ZZM1', 'ZZS', 2026, 5, 'ZZ2100', 0, 150, 'Payables', 'ZZ-TBS-M1', now(), ''),
  ('ZZM1', 'ZZS', 2026, 5, 'ZZ3000', 0, 100, 'Share capital', 'ZZ-TBS-M1', now(), ''),
  ('ZZM1', 'ZZS', 2026, 5, 'ZZ3100', 0, 550, 'Retained earnings', 'ZZ-TBS-M1', now(), '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZM1', 'ZZ-TBS-M1', 'ZZS', 2026, 5, 5, now(), 'Period-end balance');
INSERT INTO epm_staging.business_combinations
  (name, consolidation_group, acquired_entity, acquisition_date, share_acquired_pct, consideration_currency, total_consideration, net_assets_acquired, fair_value_adjustments, goodwill, bargain_purchase_gain, nci_at_acquisition, ownership_period)
VALUES
  ('BC-ZZG-ZZS-2026-03-15', 'ZZG', 'ZZS', '2026-03-15', 100, 'USD', 8300, 0, 0, 0, 0, 0, 'ZZ-OP-ZZS-1');
INSERT INTO epm_staging.business_combination_consideration
  (parent, idx, component, amount, currency, settlement_date, description)
VALUES
  ('BC-ZZG-ZZS-2026-03-15', 1, 'Cash', 8300, 'USD', '2026-03-15', 'Cash paid at completion');
