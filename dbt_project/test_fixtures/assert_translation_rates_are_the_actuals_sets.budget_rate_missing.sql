-- gate: build gold_ownership_exits gold_consolidated_trial_balance assert_translation_rates_are_the_actuals_sets
-- gate: expect gold_consolidated_trial_balance built
-- gate: expect assert_translation_rates_are_the_actuals_sets pass
-- governed_rate_guard is unaffected by the budget (konsol#348 S4 W5): the ACTUALS build goes through
-- while a BUDGET rate is missing. The twin of
-- assert_budget_translated_currency_has_a_governed_rate.guard_refuses.must_flag.sql, same rows, plus
-- a trial balance: one EUR entity ZZE1 in a USD group ZZG, 100% owned, FY2026 P6 and P7; the actuals
-- set ZZACT holds EUR->USD for both periods, the budget's set ZZBUD for P6 only, and the approved
-- Cycle ZZ-CY-2026 on ZZBUD budgets both periods. The budget build is refused for P7 (that fixture);
-- this one must BUILD gold_consolidated_trial_balance and translate at ZZACT's rates: the actuals
-- guard keys on gold_trial_balance and the actuals set, and never reads the budget's keys or sets.
-- The model also reads these declared sources, empty here: epm_staging.historical_equity_rates.
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, is_equity, fx_method, is_posting, is_retained_earnings, uses_historical_rate)
VALUES
  ('ZZ1000', 'ZZ cash', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
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
  ('ZZG', 'ZZE1', 2026, 6, '2026-06-30', 1, 'ZZG', 1, 0, 1.0, 1.0, 'full'),
  ('ZZG', 'ZZE1', 2026, 7, '2026-07-31', 1, 'ZZG', 1, 0, 1.0, 1.0, 'full');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 6, 'FY2026-P06', 'Jun 2026', 'Regular', '2026-06-01', '2026-06-30', 'Q2', 'Open'),
  (2026, 7, 'FY2026-P07', 'Jul 2026', 'Regular', '2026-07-01', '2026-07-31', 'Q3', 'Open');
INSERT INTO epm_gold.currencies
  (currency_code, currency_name, symbol, minor_unit, usd_log10)
VALUES
  ('EUR', 'Euro', 'E', 2, -0.05),
  ('USD', 'US Dollar', '$', 2, 0);
-- konsol#348 S4-Q7 (a): the one Rate Set flagged Is Actuals, and the budget's set.
INSERT INTO epm_staging.rate_sets
  (rate_set, label, is_actuals)
VALUES
  ('ZZACT', 'ZZ actuals', 1),
  ('ZZBUD', 'ZZ budget 2026', 0);
-- The live rate tables may predate konsol#348's rate_set: add it to the scratch clones first.
ALTER TABLE epm_staging.group_exchange_rates ADD COLUMN IF NOT EXISTS rate_set String;
ALTER TABLE epm_staging.historical_equity_rates ADD COLUMN IF NOT EXISTS to_currency LowCardinality(String);
ALTER TABLE epm_staging.historical_equity_rates ADD COLUMN IF NOT EXISTS rate_set String;
-- The actuals set has P6 and P7; the budget's set has P6 only.
INSERT INTO epm_staging.group_exchange_rates
  (to_currency, from_currency, fiscal_year, fiscal_period, rate_type, rate, document, rate_set)
VALUES
  ('USD', 'EUR', 2026, 6, 'Closing', 1.10, 'ZZ-GER-2026-06', 'ZZACT'),
  ('USD', 'EUR', 2026, 6, 'Average', 1.05, 'ZZ-GER-2026-06', 'ZZACT'),
  ('USD', 'EUR', 2026, 7, 'Closing', 1.20, 'ZZ-GER-2026-07', 'ZZACT'),
  ('USD', 'EUR', 2026, 7, 'Average', 1.15, 'ZZ-GER-2026-07', 'ZZACT'),
  ('USD', 'EUR', 2026, 6, 'Closing', 2.00, 'ZZ-GER-2026-06-BUD', 'ZZBUD'),
  ('USD', 'EUR', 2026, 6, 'Average', 1.90, 'ZZ-GER-2026-06-BUD', 'ZZBUD');
-- The approved Cycle and its budget, both periods, so the budget side IS missing a rate here.
INSERT INTO epm_staging.budget_cycles
  (name, scenario_id, fiscal_year, rate_set, as_of_date, horizon_periods)
VALUES
  ('ZZ-CY-2026', 'ZZ_PLAN_2026', 2026, 'ZZBUD', '2026-05-31', 12);
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_spread_budget
  (scenario_id, cycle, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, dim_department, layer, currency, annual_amount, spread_profile_id, profile_name, period_weight, period_amount, submitted_by)
VALUES
  ('ZZ_PLAN_2026', 'ZZ-CY-2026', 'ZZE1', 2026, 6, 'ZZ4000', '', '', 'base', 'EUR', -150, 'manual', 'Manual (as-entered)', 0.6667, -100, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-2026', 'ZZE1', 2026, 7, 'ZZ4000', '', '', 'base', 'EUR', -150, 'manual', 'Manual (as-entered)', 0.3333, -50, '');
-- The actuals: a trial balance for both periods.
ALTER TABLE epm_gold.gold_trial_balance_by_partner ADD COLUMN IF NOT EXISTS is_year_end_close UInt8 DEFAULT 0;
INSERT INTO epm_gold.gold_trial_balance_by_partner
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, partner_data_area_id, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZE1', 2026, 6, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, '', 100, 0, 100, 1),
  ('ZZE1', 2026, 6, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', 0, 100, -100, 1),
  ('ZZE1', 2026, 7, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, '', 50, 0, 50, 1),
  ('ZZE1', 2026, 7, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', 0, 50, -50, 1);
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZE1', 2026, 6, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 100, 0, 100, 1),
  ('ZZE1', 2026, 6, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 100, -100, 1),
  ('ZZE1', 2026, 7, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 50, 0, 50, 1),
  ('ZZE1', 2026, 7, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 50, -50, 1);
