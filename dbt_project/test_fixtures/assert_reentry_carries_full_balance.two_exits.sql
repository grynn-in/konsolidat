-- gate: build gold_ownership_exits +gold_fully_consolidated_tb gold_ownership_exit_journal assert_reentry_carries_full_balance
-- gate: expect assert_reentry_carries_full_balance pass
-- konsolidat#335 (#358 review F4 b): TWO exits of one (group, entity), each followed by a re-entry through a
-- Business Combination. Based on .gap_no_double_count: ZZJ (EUR) is 50% proportional in ZZH (USD) until
-- 2025-12-31 (bare end: exit 1, P = FY2025 P12, first period out F = FY2026 P1), out for Jan-Mar, acquired 100%
-- by BC-ZZH-ZZJ-2026-04-01 (full) until 2026-06-30 (bare end: exit 2, P = FY2026 P6, F = P7), out for Jul-Aug,
-- then acquired again 100% by BC-ZZH-ZZJ-2026-09-01 (full, open-ended). Three stints: spine_stints counts 0, 1, 2.
-- Trial balances (period-end balance): FY2025 P12, FY2026 P3, P4, P5 (cash +30 against retained earnings), P8
-- (out of the group, as P3), P9 and P10 (cash +30 again). None in P6: gold_entity_ownership has a row only where
-- a trial balance exists, and the oracle checks exit 1's re-entry in EVERY later full period, so a P6 row would be
-- checked after exit 2's journal has derecognised it (carried 0 against the full balance), a flag that is the
-- oracle's, not the model's: the test does not bound one exit's checks by the next exit (follow-up). The exit
-- journal still posts in P6, reversing what stint 2 carried through P5 and BC 1's opening balances.
-- Closing rates move at each stint: 1.10 (FY2025 P12), 1.15 (P3), 1.20 (P4, P5), 1.25 (P6), 1.28 (P8),
-- 1.30 (P9), 1.35 (P10), so a retranslation that reaches back across either exit shows up.
-- Expected (assert_reentry_carries_full_balance passes): in P4 and P5 (after exit 1) and in P9 and P10 (after
-- both exits, checked once per exit), ZZJ's non-equity closing-rate accounts sum over every FCTB layer to 100% of
-- the cumulative local balance at the period's closing rate, e.g. cash P5 130 x 1.20 = 156, P9 130 x 1.30 = 169,
-- P10 160 x 1.35 = 216. Without the second stint boundary, P10 cash would also carry stint 2's layer 1 retranslated
-- again: (cum local before P9) x (C(P9) - C(P5)), on top of BC 2's line (0).
-- Deal 2's header in group currency at the P9 closing rate: net assets 650 x 1.30 = 845, FVA 930 x 1.30 = 1,209,
-- goodwill 9,000 - 2,054 = 6,946. Deal 1's is the base fixture's (8,300; 780; 1,116; 6,404).
ALTER TABLE epm_staging.consolidation_ancestry ADD COLUMN IF NOT EXISTS path_id String, ADD COLUMN IF NOT EXISTS link_owner_group String, ADD COLUMN IF NOT EXISTS link_owner_data_area_id String;
-- The owner joins the sorting key (konsol#117): two owners of one node from one date are two rows, not one
-- ReplacingMergeTree duplicate. This is the live upgrade statement; it is a no-op on an upgraded table.
ALTER TABLE epm_staging.ownership_periods ADD COLUMN IF NOT EXISTS owner_group String, ADD COLUMN IF NOT EXISTS owner_data_area_id String, MODIFY ORDER BY (consolidation_group, data_area_id, effective_date, owner_group, owner_data_area_id);
CREATE TABLE IF NOT EXISTS epm_staging.consolidation_method_declarations (consolidation_group String, data_area_id String, consolidation_method String, effective_date Date, end_date Date DEFAULT '9999-12-31', reason String, updated_at DateTime DEFAULT now()) ENGINE = ReplacingMergeTree(updated_at) ORDER BY (consolidation_group, data_area_id, effective_date);
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
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS partial_period_treatment String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS exit_gain_loss_account String DEFAULT '';
CREATE TABLE IF NOT EXISTS epm_staging.business_combinations (name String, consolidation_group String, acquired_entity String, acquisition_date Date, share_acquired_pct Float64, consideration_currency String, total_consideration Float64, net_assets_acquired Float64, fair_value_adjustments Float64, goodwill Float64, bargain_purchase_gain Float64, nci_at_acquisition Float64, ownership_period String) ENGINE = MergeTree ORDER BY name;
ALTER TABLE epm_staging.business_combinations ADD COLUMN IF NOT EXISTS nci_measurement String DEFAULT '';
ALTER TABLE epm_staging.business_combinations ADD COLUMN IF NOT EXISTS nci_fair_value Float64 DEFAULT 0;
CREATE TABLE IF NOT EXISTS epm_staging.business_combination_consideration (parent String, idx UInt16, component String, amount Float64, currency String, settlement_date Date, description String) ENGINE = MergeTree ORDER BY (parent, idx);
CREATE TABLE IF NOT EXISTS epm_staging.business_combination_acquired_balances (parent String, idx UInt16, main_account String, book_amount Float64, fair_value_adjustment Float64, note String) ENGINE = MergeTree ORDER BY (parent, idx);
CREATE TABLE IF NOT EXISTS epm_staging.business_combination_costs (parent String, idx UInt16, kind String, amount Float64, currency String, description String) ENGINE = MergeTree ORDER BY (parent, idx);
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
  ('ZZ4960', 'ZZ gain or loss on exit', 'ZZCOA', '', 0, 'Revenue', 'Profit and Loss', 'Other income', 'Credit', 'Period', 'average', 1, 0, 0, '', '', 0, 'OTHER_INCOME', 'Published', 0),
  ('ZZ6900', 'ZZ goodwill amortisation', 'ZZCOA', '', 0, 'Expense', 'Profit and Loss', 'Operating expenses', 'Debit', 'Period', 'average', 1, 0, 0, '', '', 0, 'OPEX', 'Published', 0),
  ('ZZ6950', 'ZZ acquisition costs', 'ZZCOA', '', 0, 'Expense', 'Profit and Loss', 'Operating expenses', 'Debit', 'Period', 'average', 1, 0, 0, '', '', 0, 'OPEX', 'Published', 0);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open'),
  (2026, 2, 'FY2026-P02', 'Feb 2026', 'Regular', '2026-02-01', '2026-02-28', 'Q1', 'Open'),
  (2025, 12, 'FY2025-P12', 'Dec 2025', 'Regular', '2025-12-01', '2025-12-31', 'Q4', 'Open'),
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
  ('ZZJ', 'ZZ Target', 'ZZH', 0, 'Active', 'EUR', 'FR', '');
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency,
   nci_measurement, accounting_framework, goodwill_treatment, acquisition_costs_treatment, measurement_period, bargain_purchase,
   goodwill_account, fair_value_adjustment_account, investment_account, nci_account, bargain_purchase_gain_account,
   disposal_gain_loss_account, disposal_proceeds_account, goodwill_amortisation_expense_account, acquisition_costs_account, exit_gain_loss_account)
VALUES
  ('ZZH', '', 'ZZ Holdings', 'USD',
   'full', 'US GAAP', 'Impairment only', 'Expense', 'Off', 'Recognise gain',
   'ZZ1800', 'ZZ1900', 'ZZ3500', 'ZZ3400', 'ZZ4900',
   'ZZ4950', 'ZZ1000', 'ZZ6900', 'ZZ6950', 'ZZ4960'),
  ('ZZH', 'ZZJ', 'ZZ Target', 'USD',
   '', '', '', '', '', '',
   '', '', '', '', '',
   '', '', '', '', '');
INSERT INTO epm_staging.consolidation_hierarchy
  (consolidation_group, data_area_id, parent_group, hierarchy_level, path)
VALUES
  ('ZZH', 'ZZJ', '', 1, 'ZZH');
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZH', 'ZZJ', 'ZZH', 'ZZJ', 1, 1, 'ZZH/ZZJ', 'ZZH/ZZJ', 'ZZH', '');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id)
VALUES
  ('ZZH', 'ZZJ', '2020-01-01', '2025-12-31', 50, 'proportional', 'ZZH', ''),
  ('ZZH', 'ZZJ', '2026-04-01', '2026-06-30', 100, 'full', 'ZZH', ''),
  ('ZZH', 'ZZJ', '2026-09-01', '2149-06-06', 100, 'full', 'ZZH', '');
-- konsol#348 S4-Q7 (a): the one Rate Set flagged Is Actuals. The consolidation reads rates of
-- this set only, and its guard refuses a build with zero or two flagged sets.
INSERT INTO epm_staging.rate_sets
  (rate_set, label, is_actuals)
VALUES
  ('ZZACT', 'ZZ actuals', 1);
-- The live rate tables may predate konsol#348's rate_set: add it to the scratch clones first.
ALTER TABLE epm_staging.group_exchange_rates ADD COLUMN IF NOT EXISTS rate_set String;
INSERT INTO epm_staging.group_exchange_rates
  (to_currency, from_currency, fiscal_year, fiscal_period, rate_type, rate, document, rate_set)
VALUES
  ('USD', 'EUR', 2025, 12, 'Closing', 1.10, 'ZZ-GER-2025-12', 'ZZACT'),
  ('USD', 'EUR', 2025, 12, 'Average', 1.10, 'ZZ-GER-2025-12', 'ZZACT'),
  ('USD', 'EUR', 2026, 3, 'Closing', 1.15, 'ZZ-GER-2026-03', 'ZZACT'),
  ('USD', 'EUR', 2026, 3, 'Average', 1.15, 'ZZ-GER-2026-03', 'ZZACT'),
  ('USD', 'EUR', 2026, 4, 'Closing', 1.20, 'ZZ-GER-2026-04', 'ZZACT'),
  ('USD', 'EUR', 2026, 4, 'Average', 1.20, 'ZZ-GER-2026-04', 'ZZACT'),
  ('USD', 'EUR', 2026, 5, 'Closing', 1.20, 'ZZ-GER-2026-05', 'ZZACT'),
  ('USD', 'EUR', 2026, 5, 'Average', 1.20, 'ZZ-GER-2026-05', 'ZZACT'),
  ('USD', 'EUR', 2026, 6, 'Closing', 1.25, 'ZZ-GER-2026-06', 'ZZACT'),
  ('USD', 'EUR', 2026, 6, 'Average', 1.25, 'ZZ-GER-2026-06', 'ZZACT'),
  ('USD', 'EUR', 2026, 8, 'Closing', 1.28, 'ZZ-GER-2026-08', 'ZZACT'),
  ('USD', 'EUR', 2026, 8, 'Average', 1.28, 'ZZ-GER-2026-08', 'ZZACT'),
  ('USD', 'EUR', 2026, 9, 'Closing', 1.30, 'ZZ-GER-2026-09', 'ZZACT'),
  ('USD', 'EUR', 2026, 9, 'Average', 1.30, 'ZZ-GER-2026-09', 'ZZACT'),
  ('USD', 'EUR', 2026, 10, 'Closing', 1.35, 'ZZ-GER-2026-10', 'ZZACT'),
  ('USD', 'EUR', 2026, 10, 'Average', 1.35, 'ZZ-GER-2026-10', 'ZZACT');
INSERT INTO epm_staging.business_combinations
  (name, consolidation_group, acquired_entity, acquisition_date, share_acquired_pct, consideration_currency, total_consideration, net_assets_acquired, fair_value_adjustments, goodwill, bargain_purchase_gain, nci_at_acquisition, ownership_period, nci_measurement)
VALUES
  ('BC-ZZH-ZZJ-2026-04-01', 'ZZH', 'ZZJ', '2026-04-01', 100, 'USD', 8300, 780, 1116, 6404, 0, 0, 'ZZ-OP-ZZJ-1', 'partial'),
  ('BC-ZZH-ZZJ-2026-09-01', 'ZZH', 'ZZJ', '2026-09-01', 100, 'USD', 9000, 845, 1209, 6946, 0, 0, 'ZZ-OP-ZZJ-2', 'partial');
INSERT INTO epm_staging.business_combination_consideration
  (parent, idx, component, amount, currency, settlement_date, description)
VALUES
  ('BC-ZZH-ZZJ-2026-04-01', 1, 'Cash', 8300, 'USD', '2026-04-01', 'Cash paid at completion'),
  ('BC-ZZH-ZZJ-2026-09-01', 1, 'Cash', 9000, 'USD', '2026-09-01', 'Cash paid at completion');
INSERT INTO epm_staging.business_combination_acquired_balances
  (parent, idx, main_account, book_amount, fair_value_adjustment, note)
VALUES
  ('BC-ZZH-ZZJ-2026-04-01', 1, 'ZZ1100', 200, 0, 'Receivables'),
  ('BC-ZZH-ZZJ-2026-04-01', 2, 'ZZ1420', 600, 930, 'Plant, stepped up to fair value'),
  ('BC-ZZH-ZZJ-2026-04-01', 3, 'ZZ2100', -150, 0, 'Payables'),
  ('BC-ZZH-ZZJ-2026-04-01', 4, 'ZZ3000', -100, 0, 'Share capital'),
  ('BC-ZZH-ZZJ-2026-04-01', 5, 'ZZ3100', -550, 0, 'Retained earnings at acquisition'),
  ('BC-ZZH-ZZJ-2026-09-01', 1, 'ZZ1100', 200, 0, 'Receivables'),
  ('BC-ZZH-ZZJ-2026-09-01', 2, 'ZZ1420', 600, 930, 'Plant, stepped up to fair value'),
  ('BC-ZZH-ZZJ-2026-09-01', 3, 'ZZ2100', -150, 0, 'Payables'),
  ('BC-ZZH-ZZJ-2026-09-01', 4, 'ZZ3000', -100, 0, 'Share capital'),
  ('BC-ZZH-ZZJ-2026-09-01', 5, 'ZZ3100', -550, 0, 'Retained earnings at acquisition');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZJ0', 'ZZJ', 2025, 12, 'ZZ1000', 100, 0, 'Cash', 'ZZ-TBS-J0', now(), ''),
  ('ZZJ0', 'ZZJ', 2025, 12, 'ZZ1100', 200, 0, 'Receivables', 'ZZ-TBS-J0', now(), ''),
  ('ZZJ0', 'ZZJ', 2025, 12, 'ZZ1420', 600, 0, 'Plant', 'ZZ-TBS-J0', now(), ''),
  ('ZZJ0', 'ZZJ', 2025, 12, 'ZZ2100', 0, 150, 'Payables', 'ZZ-TBS-J0', now(), ''),
  ('ZZJ0', 'ZZJ', 2025, 12, 'ZZ3000', 0, 100, 'Share capital', 'ZZ-TBS-J0', now(), ''),
  ('ZZJ0', 'ZZJ', 2025, 12, 'ZZ3100', 0, 650, 'Retained earnings', 'ZZ-TBS-J0', now(), '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZJ0', 'ZZ-TBS-J0', 'ZZJ', 2025, 12, 6, now(), 'Period-end balance');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZJ1', 'ZZJ', 2026, 3, 'ZZ1000', 100, 0, 'Cash', 'ZZ-TBS-J1', now(), ''),
  ('ZZJ1', 'ZZJ', 2026, 3, 'ZZ1100', 200, 0, 'Receivables', 'ZZ-TBS-J1', now(), ''),
  ('ZZJ1', 'ZZJ', 2026, 3, 'ZZ1420', 600, 0, 'Plant', 'ZZ-TBS-J1', now(), ''),
  ('ZZJ1', 'ZZJ', 2026, 3, 'ZZ2100', 0, 150, 'Payables', 'ZZ-TBS-J1', now(), ''),
  ('ZZJ1', 'ZZJ', 2026, 3, 'ZZ3000', 0, 100, 'Share capital', 'ZZ-TBS-J1', now(), ''),
  ('ZZJ1', 'ZZJ', 2026, 3, 'ZZ3100', 0, 650, 'Retained earnings', 'ZZ-TBS-J1', now(), '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZJ1', 'ZZ-TBS-J1', 'ZZJ', 2026, 3, 6, now(), 'Period-end balance');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZJ2', 'ZZJ', 2026, 4, 'ZZ1000', 100, 0, 'Cash', 'ZZ-TBS-J2', now(), ''),
  ('ZZJ2', 'ZZJ', 2026, 4, 'ZZ1100', 200, 0, 'Receivables', 'ZZ-TBS-J2', now(), ''),
  ('ZZJ2', 'ZZJ', 2026, 4, 'ZZ1420', 600, 0, 'Plant', 'ZZ-TBS-J2', now(), ''),
  ('ZZJ2', 'ZZJ', 2026, 4, 'ZZ2100', 0, 150, 'Payables', 'ZZ-TBS-J2', now(), ''),
  ('ZZJ2', 'ZZJ', 2026, 4, 'ZZ3000', 0, 100, 'Share capital', 'ZZ-TBS-J2', now(), ''),
  ('ZZJ2', 'ZZJ', 2026, 4, 'ZZ3100', 0, 650, 'Retained earnings', 'ZZ-TBS-J2', now(), '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZJ2', 'ZZ-TBS-J2', 'ZZJ', 2026, 4, 6, now(), 'Period-end balance');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZJ3', 'ZZJ', 2026, 5, 'ZZ1000', 130, 0, 'Cash', 'ZZ-TBS-J3', now(), ''),
  ('ZZJ3', 'ZZJ', 2026, 5, 'ZZ1100', 200, 0, 'Receivables', 'ZZ-TBS-J3', now(), ''),
  ('ZZJ3', 'ZZJ', 2026, 5, 'ZZ1420', 600, 0, 'Plant', 'ZZ-TBS-J3', now(), ''),
  ('ZZJ3', 'ZZJ', 2026, 5, 'ZZ2100', 0, 150, 'Payables', 'ZZ-TBS-J3', now(), ''),
  ('ZZJ3', 'ZZJ', 2026, 5, 'ZZ3000', 0, 100, 'Share capital', 'ZZ-TBS-J3', now(), ''),
  ('ZZJ3', 'ZZJ', 2026, 5, 'ZZ3100', 0, 680, 'Retained earnings', 'ZZ-TBS-J3', now(), '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZJ3', 'ZZ-TBS-J3', 'ZZJ', 2026, 5, 6, now(), 'Period-end balance');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZJ4', 'ZZJ', 2026, 8, 'ZZ1000', 130, 0, 'Cash', 'ZZ-TBS-J4', now(), ''),
  ('ZZJ4', 'ZZJ', 2026, 8, 'ZZ1100', 200, 0, 'Receivables', 'ZZ-TBS-J4', now(), ''),
  ('ZZJ4', 'ZZJ', 2026, 8, 'ZZ1420', 600, 0, 'Plant', 'ZZ-TBS-J4', now(), ''),
  ('ZZJ4', 'ZZJ', 2026, 8, 'ZZ2100', 0, 150, 'Payables', 'ZZ-TBS-J4', now(), ''),
  ('ZZJ4', 'ZZJ', 2026, 8, 'ZZ3000', 0, 100, 'Share capital', 'ZZ-TBS-J4', now(), ''),
  ('ZZJ4', 'ZZJ', 2026, 8, 'ZZ3100', 0, 680, 'Retained earnings', 'ZZ-TBS-J4', now(), '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZJ4', 'ZZ-TBS-J4', 'ZZJ', 2026, 8, 6, now(), 'Period-end balance');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZJ5', 'ZZJ', 2026, 9, 'ZZ1000', 130, 0, 'Cash', 'ZZ-TBS-J5', now(), ''),
  ('ZZJ5', 'ZZJ', 2026, 9, 'ZZ1100', 200, 0, 'Receivables', 'ZZ-TBS-J5', now(), ''),
  ('ZZJ5', 'ZZJ', 2026, 9, 'ZZ1420', 600, 0, 'Plant', 'ZZ-TBS-J5', now(), ''),
  ('ZZJ5', 'ZZJ', 2026, 9, 'ZZ2100', 0, 150, 'Payables', 'ZZ-TBS-J5', now(), ''),
  ('ZZJ5', 'ZZJ', 2026, 9, 'ZZ3000', 0, 100, 'Share capital', 'ZZ-TBS-J5', now(), ''),
  ('ZZJ5', 'ZZJ', 2026, 9, 'ZZ3100', 0, 680, 'Retained earnings', 'ZZ-TBS-J5', now(), '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZJ5', 'ZZ-TBS-J5', 'ZZJ', 2026, 9, 6, now(), 'Period-end balance');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id)
VALUES
  ('ZZJ6', 'ZZJ', 2026, 10, 'ZZ1000', 160, 0, 'Cash', 'ZZ-TBS-J6', now(), ''),
  ('ZZJ6', 'ZZJ', 2026, 10, 'ZZ1100', 200, 0, 'Receivables', 'ZZ-TBS-J6', now(), ''),
  ('ZZJ6', 'ZZJ', 2026, 10, 'ZZ1420', 600, 0, 'Plant', 'ZZ-TBS-J6', now(), ''),
  ('ZZJ6', 'ZZJ', 2026, 10, 'ZZ2100', 0, 150, 'Payables', 'ZZ-TBS-J6', now(), ''),
  ('ZZJ6', 'ZZJ', 2026, 10, 'ZZ3000', 0, 100, 'Share capital', 'ZZ-TBS-J6', now(), ''),
  ('ZZJ6', 'ZZJ', 2026, 10, 'ZZ3100', 0, 710, 'Retained earnings', 'ZZ-TBS-J6', now(), '');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZJ6', 'ZZ-TBS-J6', 'ZZJ', 2026, 10, 6, now(), 'Period-end balance');
