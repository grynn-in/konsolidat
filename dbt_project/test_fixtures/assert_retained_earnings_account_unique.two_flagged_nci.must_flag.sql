-- gate: expect assert_retained_earnings_account_unique flag 1
-- gate: expect assert_retained_earnings_account_unique assert_nci_attribution_equals_minority_result pass
-- konsolidat#316 7b: nci_attribution_journal.sql with a SECOND chart account (ZZ3200) flagged is_retained_earnings.
-- Before 7b the NCI journal silently posted its RE line on the lowest code (ZZ3100); now it posts on '' and
-- assert_retained_earnings_account_unique names group ZZP (count 2). The journal stays balanced (the oracle passes).
-- Not red on the base: the 7a test already flags an NCI row on ZZ3100 with count 2; the change is pinned by the
-- oracle passing and a grep that the lowest-code pick is gone.
-- gate: build gold_entity_ownership gold_consolidated_trial_balance gold_acquisition_adjustments gold_business_combination_journal gold_business_disposal_journal gold_consolidation_adjustments gold_equity_method_associates gold_fx_revaluation gold_goodwill_amortisation_journal gold_ic_reconciliation gold_ic_eliminations gold_nci_attribution_journal gold_fully_consolidated_tb assert_retained_earnings_account_unique assert_nci_attribution_equals_minority_result assert_all_layers_present assert_nci_account_declared_for_partial_subs assert_end_to_end_bs_balances gold_consolidated_cash_flow assert_consolidated_cf_reconciles assert_cash_flow_excludes_nci_attribution assert_closing_period_activity_on_partial_subsidiary gold_nci_movement_schedule assert_nci_movement_reconciles assert_no_ownership_step_on_partial_full_subsidiary
-- konsol#117 pair 2 K2 (konsolidat#204 option (a), IFRS 10.B94): the minority's share of a subsidiary's result and
-- CTA is one NCI journal per (group, entity, FY, period). ZZP (USD, root) holds 70% of ZZC (SEK, method full).
-- FY2026 P3 in SEK: receivables +600, cost +400, revenue -1,000 (a local profit of 600). Governed SEK->USD P3:
-- Closing 0.10, Average 0.09. Translated: receivables 60, cost 36, revenue -90 (sum +6), so the CTA plug is -6.
--   result_share = 0.30 x (36 - 90) = -16.20 | cta_share = 0.30 x -6 = -1.80
--   Journal NCI-ZZP-ZZC-2026-P3 (USD): ZZ3100 +16.20 (Dr RE) | CTA +1.80 | ZZ3400 -18.00 (Cr NCI) -> sums to 0.
-- FY2026 P13 (Closing): the year-end close silver_tb_movements synthesizes (konsolidat#259) moves the year's P&L
-- into retained earnings: ZZ4000 +1,300, ZZ5000 -500, ZZ3100 -800 SEK (the whole year, P3 + P4), all is_year_end_close = 1. Read as P13
-- activity it reverses the year (NCI +18.00 style entry, result_share +16.20). Expected: NO journal in P13: the
-- close is excluded from result_share and the close period's CTA plug is 0.
-- FY2026 P4 (review fix, finding 8c): a second activity period at a DIFFERENT Closing rate, so the CTA attribution is
-- exercised twice. SEK->USD P4: Closing 0.12, Average 0.11. Local: receivables +200, cost +100, revenue -300 (profit 200).
-- The receivable's opening 600 is retranslated from 0.10 to 0.12 and the P&L translates at 0.11, so the entity's CTA
-- plug of P4 differs from P3's; the journal NCI-ZZP-ZZC-2026-P4 carries 30% of that period's result and of that plug,
-- and the oracle in assert_nci_attribution_equals_minority_result checks every line of it separately.
-- The NCI movement schedule agrees (finding 5): share_of_profit is 0 in P13 (the close rows are left out as the
-- journal leaves them out) and -16.20 in P3; its closing balance in P3 is the minority's share of net assets at
-- the closing rate, 0.30 x 600 x 0.10 = 18.00; P4 adds the P4 movement and the retranslation (0.30 x 800 x 0.12 = 28.80 in all);
-- P13 adds nothing (the close moves only equity).
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
  ('ZZ3200', 'ZZ retained earnings 2', 'Equity', 'Equity', 0, 1, 1, 'closing', 1, 1, 0),
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
  (2026, 3, 'FY2026-P03', 'Mar 2026', 'Regular', '2026-03-01', '2026-03-31', 'Q1', 'Open'),
  (2026, 4, 'FY2026-P04', 'Apr 2026', 'Regular', '2026-04-01', '2026-04-30', 'Q2', 'Open'),
  (2026, 13, 'FY2026-P13', 'FY2026 closing', 'Closing', '2026-12-31', '2026-12-31', 'Q4', 'Open');
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
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, partner_data_area_id, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZC', 2026, 3, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, '', 600, 0, 600, 1),
  ('ZZC', 2026, 3, 'ZZ5000', 'ZZ cost', 'Expense', 0, 1, '', 400, 0, 400, 1),
  ('ZZC', 2026, 3, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', 0, 1000, -1000, 1);
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZC', 2026, 3, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, 600, 0, 600, 1),
  ('ZZC', 2026, 3, 'ZZ5000', 'ZZ cost', 'Expense', 0, 1, 400, 0, 400, 1),
  ('ZZC', 2026, 3, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 1000, -1000, 1);
INSERT INTO epm_staging.group_exchange_rates
  (to_currency, from_currency, fiscal_year, fiscal_period, rate_type, rate, document)
VALUES
  ('USD', 'SEK', 2026, 3, 'Closing', 0.10, 'ZZ-GER-2026-03'),
  ('USD', 'SEK', 2026, 3, 'Average', 0.09, 'ZZ-GER-2026-03'),
  ('USD', 'SEK', 2026, 4, 'Closing', 0.12, 'ZZ-GER-2026-04'),
  ('USD', 'SEK', 2026, 4, 'Average', 0.11, 'ZZ-GER-2026-04');
INSERT INTO epm_gold.gold_trial_balance_by_partner
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, partner_data_area_id, period_debit, period_credit, period_net_amount, transaction_count, is_year_end_close)
VALUES
  ('ZZC', 2026, 13, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', 1300, 0, 1300, 1, 1),
  ('ZZC', 2026, 13, 'ZZ5000', 'ZZ cost', 'Expense', 0, 1, '', 0, 500, -500, 1, 1),
  ('ZZC', 2026, 13, 'ZZ3100', 'ZZ retained earnings', 'Equity', 1, 0, '', 0, 800, -800, 1, 1);
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZC', 2026, 13, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 1300, 0, 1300, 1),
  ('ZZC', 2026, 13, 'ZZ5000', 'ZZ cost', 'Expense', 0, 1, 0, 500, -500, 1),
  ('ZZC', 2026, 13, 'ZZ3100', 'ZZ retained earnings', 'Equity', 1, 0, 0, 800, -800, 1);
INSERT INTO epm_gold.gold_trial_balance_by_partner
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, partner_data_area_id, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZC', 2026, 4, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, '', 200, 0, 200, 1),
  ('ZZC', 2026, 4, 'ZZ5000', 'ZZ cost', 'Expense', 0, 1, '', 100, 0, 100, 1),
  ('ZZC', 2026, 4, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', 0, 300, -300, 1);
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZC', 2026, 4, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, 200, 0, 200, 1),
  ('ZZC', 2026, 4, 'ZZ5000', 'ZZ cost', 'Expense', 0, 1, 100, 0, 100, 1),
  ('ZZC', 2026, 4, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 300, -300, 1);
