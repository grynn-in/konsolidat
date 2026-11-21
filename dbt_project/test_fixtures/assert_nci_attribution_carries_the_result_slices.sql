-- gate: build gold_ownership_exits gold_entity_ownership gold_consolidated_trial_balance gold_acquisition_adjustments gold_business_combination_journal gold_business_disposal_journal gold_consolidation_adjustments gold_equity_method_associates gold_fx_revaluation gold_goodwill_amortisation_journal gold_ic_reconciliation gold_ic_eliminations gold_nci_attribution_journal gold_ic_side_slices gold_ownership_exit_journal gold_fully_consolidated_tb assert_nci_attribution_equals_minority_result assert_nci_attribution_carries_the_result_slices assert_sliceless_layers_carry_no_dimension assert_all_layers_present assert_nci_account_declared_for_partial_subs assert_end_to_end_bs_balances gold_consolidated_cash_flow assert_consolidated_cf_reconciles assert_cash_flow_excludes_nci_attribution assert_closing_period_activity_on_partial_subsidiary gold_nci_movement_schedule assert_nci_movement_reconciles assert_no_ownership_step_on_partial_full_subsidiary
-- gate: expect assert_nci_attribution_carries_the_result_slices pass
-- gate: expect assert_nci_attribution_equals_minority_result pass
-- gate: expect assert_sliceless_layers_carry_no_dimension pass
-- gate: expect assert_all_layers_present pass
-- gate: expect assert_end_to_end_bs_balances pass
-- konsolidat#245 option D (Deepak Pai, 3 Oct 2026; inherit where derivable): the NCI attribution inherits the
-- dimension slices of the subsidiary's P&L. ZZP (USD, root) holds 70% of ZZC (SEK, method full). FY2026 P3 in SEK,
-- the same totals as nci_attribution_journal.sql, with the P&L on two cost centres:
--   receivables +600 (no slice) | cost +400 ZZ-NORTH | revenue -800 ZZ-NORTH | revenue -200 ZZ-SOUTH
-- SEK->USD P3: Closing 0.10, Average 0.09. Translated: receivables 60, cost 36 N, revenue -72 N, -18 S.
--   ZZ-NORTH result 36 - 72 = -36 -> share 0.30 x -36 = -10.80 | ZZ-SOUTH -18 -> share -5.40
--   CTA plug -6 (entity-level, no slice) -> cta_share -1.80
-- Expected in the 'nci_attribution' layer of gold_fully_consolidated_tb:
--   ZZ-NORTH: ZZ3100 +10.80 | ZZ3400 -10.80
--   ZZ-SOUTH: ZZ3100  +5.40 | ZZ3400  -5.40
--   blank:    CTA     +1.80 | ZZ3400  -1.80
-- Totals as before (ZZ3100 +16.20, CTA +1.80, ZZ3400 -18.00); every slice nets to zero. On the base every line
-- was blank, so the two sliced retained-earnings lines were missing and the test flagged them.
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
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS ic_difference_account String DEFAULT '';
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS ic_difference_tolerance Float64 DEFAULT 0;
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS nci_account String DEFAULT '';
-- The live tables may predate konsol#117's graph columns and the declarations table: bring the
-- scratch clones to the shape the macro reads.
ALTER TABLE epm_staging.consolidation_ancestry ADD COLUMN IF NOT EXISTS path_id String, ADD COLUMN IF NOT EXISTS link_owner_group String, ADD COLUMN IF NOT EXISTS link_owner_data_area_id String;
-- The owner joins the sorting key (konsol#117): two owners of one node from one date are two rows, not one
-- ReplacingMergeTree duplicate. This is the live upgrade statement; it is a no-op on an upgraded table.
ALTER TABLE epm_staging.ownership_periods ADD COLUMN IF NOT EXISTS owner_group String, ADD COLUMN IF NOT EXISTS owner_data_area_id String, MODIFY ORDER BY (consolidation_group, data_area_id, effective_date, owner_group, owner_data_area_id);
CREATE TABLE IF NOT EXISTS epm_staging.consolidation_method_declarations (consolidation_group String, data_area_id String, consolidation_method String, effective_date Date, end_date Date DEFAULT '9999-12-31', reason String, updated_at DateTime DEFAULT now()) ENGINE = ReplacingMergeTree(updated_at) ORDER BY (consolidation_group, data_area_id, effective_date);
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZP', 'ZZC', 'ZZP', 'ZZC', 1, 1, 'ZZP/ZZC', 'ZZP/ZZC', 'ZZP', '');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id)
VALUES
  ('ZZP', 'ZZC', '2020-01-01', '2149-06-06', 70, 'full', 'ZZP', '');
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, is_equity, fx_method, is_posting, is_retained_earnings, uses_historical_rate)
VALUES
  ('ZZ1100', 'ZZ receivables', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ5000', 'ZZ cost', 'Expense', 'Expense', 1, 0, 0, 'average', 1, 0, 0),
  ('ZZ4000', 'ZZ revenue', 'Revenue', 'Revenue', 1, 0, 0, 'average', 1, 0, 0),
  ('ZZ3100', 'ZZ retained earnings', 'Equity', 'Equity', 0, 1, 1, 'closing', 1, 1, 0),
  ('ZZ3400', 'ZZ non-controlling interest', 'Equity', 'Equity', 0, 1, 1, 'closing', 1, 0, 0);
INSERT INTO epm_silver.silver_entity_currencies
  (data_area_id, accounting_currency)
VALUES
  ('ZZC', 'SEK');
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency, nci_account)
VALUES
  ('ZZP', '',    'ZZ Parent', 'USD', 'ZZ3400'),
  ('ZZP', 'ZZC', 'ZZ Controlled at 70', 'USD', '');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 3, 'FY2026-P03', 'Mar 2026', 'Regular', '2026-03-01', '2026-03-31', 'Q1', 'Open');
-- Finding 6: the NCI account maps to a Financing line; only the attribution layer touches it, so a
-- cash-flow row for that line would be the attribution shown as a cash flow.
INSERT INTO epm_staging.cash_flow_categories
  (main_account, cf_category, cf_line_item, is_cash, status)
VALUES
  ('ZZ3400', 'Financing', 'ZZ non-controlling interest', 0, 'Published');
INSERT INTO epm_gold.currencies
  (currency_code, currency_name, symbol, minor_unit, usd_log10)
VALUES
  ('USD', 'US Dollar', '$', 2, 0),
  ('SEK', 'Swedish Krona', 'kr', 2, 1);
-- The live table may predate konsolidat#259's close flag: add it to the scratch clone first.
ALTER TABLE epm_gold.gold_trial_balance_by_partner ADD COLUMN IF NOT EXISTS is_year_end_close UInt8 DEFAULT 0;
INSERT INTO epm_gold.gold_trial_balance_by_partner
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, partner_data_area_id, dim_cost_center, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZC', 2026, 3, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, '', '', 600, 0, 600, 1),
  ('ZZC', 2026, 3, 'ZZ5000', 'ZZ cost', 'Expense', 0, 1, '', 'ZZ-NORTH', 400, 0, 400, 1),
  ('ZZC', 2026, 3, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', 'ZZ-NORTH', 0, 800, -800, 1),
  ('ZZC', 2026, 3, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', 'ZZ-SOUTH', 0, 200, -200, 1);
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZC', 2026, 3, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, 600, 0, 600, 1),
  ('ZZC', 2026, 3, 'ZZ5000', 'ZZ cost', 'Expense', 0, 1, 400, 0, 400, 1),
  ('ZZC', 2026, 3, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 1000, -1000, 1);
-- konsol#348 S4-Q7 (a): the one Rate Set flagged Is Actuals; the consolidation reads rates of this set only.
INSERT INTO epm_staging.rate_sets
  (rate_set, label, is_actuals)
VALUES
  ('ZZACT', 'ZZ actuals', 1);
-- The live rate tables may predate konsol#348's rate_set: add it to the scratch clones first.
ALTER TABLE epm_staging.group_exchange_rates ADD COLUMN IF NOT EXISTS rate_set String;
INSERT INTO epm_staging.group_exchange_rates
  (to_currency, from_currency, fiscal_year, fiscal_period, rate_type, rate, document, rate_set)
VALUES
  ('USD', 'SEK', 2026, 3, 'Closing', 0.10, 'ZZ-GER-2026-03', 'ZZACT'),
  ('USD', 'SEK', 2026, 3, 'Average', 0.09, 'ZZ-GER-2026-03', 'ZZACT');
