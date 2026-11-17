-- gate: build gold_ownership_exits gold_consolidated_trial_balance assert_translation_rates_are_the_actuals_sets assert_equity_historical_rate_is_asof assert_bs_translated_at_closing_rate
-- assert_translation_rates_are_the_actuals_sets (konsol#348 S4 W2, S4-Q1 c): must PASS. Two Rate Sets
-- hold different rates for the same keys; the actuals consolidation translates at the flagged set's
-- rates only, and the build goes through.
--
-- The rows of assert_bs_translated_at_closing_rate.sql (one EUR entity ZZE1 in a USD group ZZG, 100%
-- owned, FY2026 P1 and P2; ZZ3000 share capital now declared historical with a tranche), plus a
-- second Rate Set ZZBUD (a budget's) holding, for every one of the same keys, a rate that differs:
--   EUR->USD FY2026 P1: ZZACT closing 1.10 / average 1.05;  ZZBUD closing 2.00 / average 1.90
--   EUR->USD FY2026 P2: ZZACT closing 1.20 / average 1.15;  ZZBUD closing 2.20 / average 2.10
--   ZZG / ZZE1 / ZZ3000 historical tranche: ZZACT 1.30 dated 2025-01-01;  ZZBUD 1.50 dated 2025-06-01
-- Before the rate tables carried rate_set the model read every row: the governed-rate guard counted
-- two Closing and two Average rates per key and REFUSED the build as 'duplicate' (and the ASOF join
-- took the later ZZBUD tranche). Now the model, the guard and the three tests read the ZZACT set only:
-- closing_rate / average_rate on every translated row are 1.10/1.05 and 1.20/1.15, the historical
-- rate is 1.30, and the balance-sheet retranslation uses the ZZACT closing rates.
-- The model's other inputs are named here so the gate creates them (empty): none; both rate tables
-- are seeded.
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, is_equity, fx_method, is_posting, is_retained_earnings, uses_historical_rate)
VALUES
  ('ZZ1000', 'ZZ cash', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ1100', 'ZZ bank', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ2000', 'ZZ payables', 'Liability', 'Liability', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ3000', 'ZZ share capital', 'Equity', 'Equity', 0, 1, 1, 'historical', 1, 0, 1),
  ('ZZ4000', 'ZZ revenue', 'Revenue', 'Revenue', 1, 0, 0, 'average', 1, 0, 0);
INSERT INTO epm_silver.silver_entity_currencies
  (data_area_id, accounting_currency)
VALUES
  ('ZZE1', 'EUR');
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency)
VALUES
  ('ZZG', '', 'ZZ Group', 'USD'),
  ('ZZG', 'ZZE1', 'ZZ Entity 1', 'USD');
INSERT INTO epm_gold.gold_entity_ownership
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, period_date, chain_depth, owner_group, has_complete_chain, outside_ownership_window, effective_ownership_pct, direct_ownership_pct, consolidation_method)
VALUES
  ('ZZG', 'ZZE1', 2026, 1, '2026-01-31', 1, 'ZZG', 1, 0, 1.0, 1.0, 'full'),
  ('ZZG', 'ZZE1', 2026, 2, '2026-02-28', 1, 'ZZG', 1, 0, 1.0, 1.0, 'full');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open'),
  (2026, 2, 'FY2026-P02', 'Feb 2026', 'Regular', '2026-02-01', '2026-02-28', 'Q1', 'Open');
INSERT INTO epm_gold.currencies
  (currency_code, currency_name, symbol, minor_unit, usd_log10)
VALUES
  ('EUR', 'Euro', 'E', 2, -0.05),
  ('USD', 'US Dollar', '$', 2, 0);
-- konsol#348 S4-Q7 (a): two Rate Sets; ZZACT is the one flagged Is Actuals.
INSERT INTO epm_staging.rate_sets
  (rate_set, label, is_actuals)
VALUES
  ('ZZACT', 'ZZ actuals', 1),
  ('ZZBUD', 'ZZ budget 2026', 0);
-- The live rate tables may predate konsol#348's rate_set: add it to the scratch clones first.
ALTER TABLE epm_staging.group_exchange_rates ADD COLUMN IF NOT EXISTS rate_set String;
INSERT INTO epm_staging.group_exchange_rates
  (to_currency, from_currency, fiscal_year, fiscal_period, rate_type, rate, document, rate_set)
VALUES
  ('USD', 'EUR', 2026, 1, 'Closing', 1.10, 'ZZ-GER-2026-01', 'ZZACT'),
  ('USD', 'EUR', 2026, 1, 'Average', 1.05, 'ZZ-GER-2026-01', 'ZZACT'),
  ('USD', 'EUR', 2026, 2, 'Closing', 1.20, 'ZZ-GER-2026-02', 'ZZACT'),
  ('USD', 'EUR', 2026, 2, 'Average', 1.15, 'ZZ-GER-2026-02', 'ZZACT'),
  ('USD', 'EUR', 2026, 1, 'Closing', 2.00, 'ZZ-GER-2026-01-BUD', 'ZZBUD'),
  ('USD', 'EUR', 2026, 1, 'Average', 1.90, 'ZZ-GER-2026-01-BUD', 'ZZBUD'),
  ('USD', 'EUR', 2026, 2, 'Closing', 2.20, 'ZZ-GER-2026-02-BUD', 'ZZBUD'),
  ('USD', 'EUR', 2026, 2, 'Average', 2.10, 'ZZ-GER-2026-02-BUD', 'ZZBUD');
ALTER TABLE epm_staging.historical_equity_rates ADD COLUMN IF NOT EXISTS to_currency LowCardinality(String);
ALTER TABLE epm_staging.historical_equity_rates ADD COLUMN IF NOT EXISTS rate_set String;
-- The budget's tranche is dated later, so an unfiltered ASOF join would take it over the actuals'.
INSERT INTO epm_staging.historical_equity_rates
  (consolidation_group, data_area_id, main_account, rate_date, historical_rate, to_currency, rate_set)
VALUES
  ('ZZG', 'ZZE1', 'ZZ3000', '2025-01-01', 1.30, 'USD', 'ZZACT'),
  ('ZZG', 'ZZE1', 'ZZ3000', '2025-06-01', 1.50, 'USD', 'ZZBUD');
-- The live table may predate konsolidat#259's close flag: add it to the scratch clone first.
ALTER TABLE epm_gold.gold_trial_balance_by_partner ADD COLUMN IF NOT EXISTS is_year_end_close UInt8 DEFAULT 0;
INSERT INTO epm_gold.gold_trial_balance_by_partner
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, partner_data_area_id, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZE1', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, '', 100, 0, 100, 1),
  ('ZZE1', 2026, 1, 'ZZ2000', 'ZZ payables', 'Liability', 1, 0, '', 0, 60, -60, 1),
  ('ZZE1', 2026, 1, 'ZZ3000', 'ZZ share capital', 'Equity', 1, 0, '', 0, 40, -40, 1),
  ('ZZE1', 2026, 2, 'ZZ1100', 'ZZ bank', 'Asset', 1, 0, '', 50, 0, 50, 1),
  ('ZZE1', 2026, 2, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', 0, 50, -50, 1);
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZE1', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 100, 0, 100, 1),
  ('ZZE1', 2026, 1, 'ZZ2000', 'ZZ payables', 'Liability', 1, 0, 0, 60, -60, 1),
  ('ZZE1', 2026, 1, 'ZZ3000', 'ZZ share capital', 'Equity', 1, 0, 0, 40, -40, 1),
  ('ZZE1', 2026, 2, 'ZZ1100', 'ZZ bank', 'Asset', 1, 0, 50, 0, 50, 1),
  ('ZZE1', 2026, 2, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 50, -50, 1);
