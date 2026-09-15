-- Goodwill amortisation stops at the disposal (konsolidat#198 row J5b, design §1 "until fully amortised or
-- disposal"): `+gold_goodwill_amortisation_journal assert_goodwill_amortisation_journal_balances` must BUILD
-- and PASS on these rows, and the schedule must hold 12 instalments, not 120. (Since row J5cb each journal has
-- its own balance test, so this selector is self-contained; the disposal journal itself is proved under
-- `+gold_business_disposal_journal assert_disposal_journal_balances`.)
--
-- goodwill_amortisation.sql (row J5) plus one submitted Business Disposal: the group sells 100% of ZZS on
-- 2027-03-31 (FY2027 P3, BD-ZZG-ZZS-2027-03-31, 9,000 USD). The amortisation journal posts in every Regular
-- period from the acquisition period up to but NOT including the disposal period, so the disposal journal
-- (gold_business_disposal_journal, not selected by this gate) derecognises goodwill net of the amortisation
-- to date: FY2026 P3 .. FY2027 P2 = 12 instalments of 56 = 672 amortised, 6,048 left to derecognise.
--
-- Expected journal GWA-ZZG-ZZS-2026-03-15 (USD): 12 periods x (Dr ZZ6900 56 / Cr ZZ1800 56) = 24 rows, every
-- period sums to 0, the 12 expense lines sum to 672, instalments 1..12 of n_instalments 120, last period
-- FY2027 P2; FY2027 P3 and later carry nothing.
--
-- The deal, as in goodwill_amortisation.sql: the J2 deal (business_combination_100pct.sql) under a group whose goodwill policy is Amortise over 10 years:
-- group ZZG (USD; IFRS, NCI partial, goodwill Amortise / goodwill_amortisation_years 10, costs Expense,
-- measurement period Off, bargain purchase Recognise gain) with its accounts declared on the root row:
--   ZZ1800 goodwill | ZZ1900 fair-value adjustment | ZZ3500 investment | ZZ3400 NCI | ZZ4900 bargain gain
--   ZZ4950 disposal gain/loss | ZZ1000 proceeds (cash) | ZZ6900 amortisation expense | ZZ6950 acquisition costs
-- Entity ZZS (EUR) is acquired on 2026-03-15 (FY2026 P3) for 8,300 USD cash against fair-value net assets
-- 1,580 USD (book 650 + FVA 930), so the acquisition journal ACQ-ZZG-ZZS-2026-03-15 books goodwill 6,720
-- (EUR->USD Closing 1.0 at P3; the amortisation journal itself is in group currency and needs no rate).
--
-- Calendar: FY2026..FY2036, 12 Regular periods (P1..P12) and one Closing period (P13) per year, generated
-- from numbers() so the eleven years read as one statement; the acquisition year has 12 Regular periods.
--
-- Without the disposal the schedule would run 10 years x 12 Regular periods = 120 instalments of 6,720 / 120
-- = 56 each, FY2026 P3 .. FY2036 P2 (240 rows; goodwill_amortisation.sql proves that).
--
-- The six deal tables do not exist live yet: the fixture creates the six the three journals read (the costs
-- and disposal-proceeds tables are empty here: no acquisition costs, and the disposal journal falls back to
-- the header's total_proceeds) with konsol's exact DDL (clickhouse/init-db.sql, pinned by
-- tests/test_deal_tables_ddl.py). The live consolidation_groups, main_accounts and submission control may
-- predate their policy/flag/basis columns: add them first. The disposal journal's lineage
-- (gold_consolidated_trial_balance, gold_fx_revaluation) reads the hierarchy, ancestry, ownership and currency
-- rows of the group, so they are here too; ZZS uploads no trial balance, so the disposal journal derecognises
-- only goodwill 6,048 (6,720 - 672) and FVA 930 against proceeds 9,000 and it balances by construction.
-- The acquisition journal reads gold_trial_balance (pre-acquisition history), whose lineage reads these tables,
-- empty on a trial-balance-only site with no upload, so they are named here to exist (empty):
-- epm_raw.trial_balance_submissions, epm_raw.trial_balance_submission_control,
-- epm_raw.general_journal_account_entry_bi_entities, epm_raw.general_journal_entry_bi_entities, epm_raw.ledgers,
-- epm_raw.legal_entities, epm_raw.fiscal_calendar_years, epm_gold.entity_fiscal_calendars,
-- epm_staging.historical_equity_rates, epm_staging.dimension_mappings.
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
ALTER TABLE epm_staging.business_combinations ADD COLUMN IF NOT EXISTS nci_measurement String DEFAULT '';
ALTER TABLE epm_staging.business_combinations ADD COLUMN IF NOT EXISTS nci_fair_value Float64 DEFAULT 0;
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
SELECT
  toUInt16(2026 + intDiv(number, 12)) AS fiscal_year,
  toUInt8(number % 12 + 1) AS fiscal_period,
  concat('FY', toString(fiscal_year), '-P', leftPad(toString(fiscal_period), 2, '0')) AS period_code,
  formatDateTime(addMonths(toDate('2026-01-01'), number), '%b %Y') AS period_label,
  'Regular' AS period_type,
  addMonths(toDate('2026-01-01'), number) AS start_date,
  toLastDayOfMonth(start_date) AS end_date,
  concat('Q', toString(intDiv(number % 12, 3) + 1)) AS quarter,
  'Open' AS status
FROM numbers(132);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
SELECT
  toUInt16(2026 + number) AS fiscal_year,
  toUInt8(13) AS fiscal_period,
  concat('FY', toString(fiscal_year), '-P13') AS period_code,
  concat('FY', toString(fiscal_year), ' closing') AS period_label,
  'Closing' AS period_type,
  toDate(concat(toString(fiscal_year), '-12-31')) AS start_date,
  start_date AS end_date,
  'Q4' AS quarter,
  'Open' AS status
FROM numbers(11);
INSERT INTO epm_staging.entities
  (data_area_id, entity_name, parent_entity, is_group, status, accounting_currency, country, erp_source)
VALUES
  ('ZZS', 'ZZ Subsidiary', 'ZZG', 0, 'Active', 'EUR', 'DE', '');
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency,
   nci_measurement, accounting_framework, goodwill_treatment, goodwill_amortisation_years, acquisition_costs_treatment, measurement_period, bargain_purchase,
   goodwill_account, fair_value_adjustment_account, investment_account, nci_account, bargain_purchase_gain_account,
   disposal_gain_loss_account, disposal_proceeds_account, goodwill_amortisation_expense_account, acquisition_costs_account)
VALUES
  ('ZZG', '', 'ZZ Group', 'USD',
   'partial', 'IFRS', 'Amortise', 10, 'Expense', 'Off', 'Recognise gain',
   'ZZ1800', 'ZZ1900', 'ZZ3500', 'ZZ3400', 'ZZ4900',
   'ZZ4950', 'ZZ1000', 'ZZ6900', 'ZZ6950'),
  ('ZZG', 'ZZS', 'ZZ Subsidiary', 'USD',
   '', '', '', 0, '', '', '',
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
  ('USD', 'EUR', 2026, 3, 'Average', 1.0, 'ZZ-GER-2026-03'),
  ('USD', 'EUR', 2027, 3, 'Closing', 1.0, 'ZZ-GER-2027-03'),
  ('USD', 'EUR', 2027, 3, 'Average', 1.0, 'ZZ-GER-2027-03');
INSERT INTO epm_staging.business_combinations
  (name, consolidation_group, acquired_entity, acquisition_date, share_acquired_pct, consideration_currency, total_consideration, net_assets_acquired, fair_value_adjustments, goodwill, bargain_purchase_gain, nci_at_acquisition, ownership_period, nci_measurement)
VALUES
  ('BC-ZZG-ZZS-2026-03-15', 'ZZG', 'ZZS', '2026-03-15', 100, 'USD', 8300, 650, 930, 6720, 0, 0, 'ZZ-OP-ZZS-1', 'partial');
INSERT INTO epm_staging.business_combination_consideration
  (parent, idx, component, amount, currency, settlement_date, description)
VALUES
  ('BC-ZZG-ZZS-2026-03-15', 1, 'Cash', 8300, 'USD', '2026-03-15', 'Cash paid at completion');
INSERT INTO epm_staging.business_combination_acquired_balances
  (parent, idx, main_account, book_amount, fair_value_adjustment, note)
VALUES
  ('BC-ZZG-ZZS-2026-03-15', 1, 'ZZ1100', 200, 0, 'Receivables'),
  ('BC-ZZG-ZZS-2026-03-15', 2, 'ZZ1420', 600, 930, 'Plant, stepped up to fair value'),
  ('BC-ZZG-ZZS-2026-03-15', 3, 'ZZ2100', -150, 0, 'Payables'),
  ('BC-ZZG-ZZS-2026-03-15', 4, 'ZZ3000', -100, 0, 'Share capital'),
  ('BC-ZZG-ZZS-2026-03-15', 5, 'ZZ3100', -550, 0, 'Retained earnings at acquisition');
INSERT INTO epm_staging.business_disposals
  (name, consolidation_group, disposed_entity, disposal_date, share_disposed_pct, retained_interest_pct, proceeds_currency, total_proceeds, ownership_period)
VALUES
  ('BD-ZZG-ZZS-2027-03-31', 'ZZG', 'ZZS', '2027-03-31', 100, 0, 'USD', 9000, 'ZZ-OP-ZZS-1');
