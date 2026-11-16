-- gate: build gold_consolidated_budget_tb assert_budget_consolidated_periods_complete
-- gate: expect gold_consolidated_budget_tb built
-- gate: expect assert_budget_consolidated_periods_complete pass
-- assert_budget_consolidated_periods_complete (konsol#348 S4 W4): must PASS, and the model must build.
-- A budget period with NO trial balance row is translated and consolidated.
--
-- One EUR entity ZZE1 in a USD group ZZG, 100% owned since 2020 (a dated link in
-- consolidation_ancestry / ownership_periods, so ownership is resolved on the budget's own spine).
-- The approved Cycle ZZ-CY-2026 (scenario ZZ_PLAN_2026, Rate Set ZZBUD) budgets FY2026 P6 and P7.
-- The ACTUALS know P6 only: gold_trial_balance and gold_entity_ownership hold P6 and nothing for P7
-- (they are seeded to document that; the model does not read them). Before W4 the consolidation's
-- ownership came from gold_entity_ownership, whose spine is the actuals' periods, so P7 had no
-- ownership row and the whole budget period vanished from an inner join with nothing failing.
-- Rates: ZZBUD holds EUR->USD for P6 and P7; ZZACT (the actuals set) holds P6 ONLY, so a budget
-- that fell back to the actuals set would be refused at P7, and one that read every set would see
-- two Closing rates at P6. Both periods must come out translated at ZZBUD's rates
-- (P6 closing 1.10 / average 1.05, P7 closing 1.20 / average 1.15).
-- Budget dimensions at the fixture dims are dim_cost_center and dim_department; a live
-- gold_spread_budget built at other dims gets them by ALTER first.
-- The model also reads these declared sources, empty here: epm_staging.historical_equity_rates,
-- epm_staging.consolidation_method_declarations, epm_staging.business_disposals, epm_gold.currencies
-- (seeded, for the guard's magnitude check).
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
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZG', 'ZZE1', 'ZZG', 'ZZE1', 1, 1, 'ZZG/ZZE1', 'ZZG/ZZE1', 'ZZG', '');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id)
VALUES
  ('ZZG', 'ZZE1', '2020-01-01', '2149-06-06', 100, 'full', 'ZZG', '');
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
INSERT INTO epm_staging.group_exchange_rates
  (to_currency, from_currency, fiscal_year, fiscal_period, rate_type, rate, document, rate_set)
VALUES
  ('USD', 'EUR', 2026, 6, 'Closing', 1.10, 'ZZ-GER-2026-06-BUD', 'ZZBUD'),
  ('USD', 'EUR', 2026, 6, 'Average', 1.05, 'ZZ-GER-2026-06-BUD', 'ZZBUD'),
  ('USD', 'EUR', 2026, 7, 'Closing', 1.20, 'ZZ-GER-2026-07-BUD', 'ZZBUD'),
  ('USD', 'EUR', 2026, 7, 'Average', 1.15, 'ZZ-GER-2026-07-BUD', 'ZZBUD'),
  ('USD', 'EUR', 2026, 6, 'Closing', 1.00, 'ZZ-GER-2026-06', 'ZZACT'),
  ('USD', 'EUR', 2026, 6, 'Average', 1.00, 'ZZ-GER-2026-06', 'ZZACT');
-- konsol#348 S4-Q2 (a): the approved Cycle, with the Rate Set it declares (BUD-3).
INSERT INTO epm_staging.budget_cycles
  (name, scenario_id, fiscal_year, rate_set, as_of_date, horizon_periods)
VALUES
  ('ZZ-CY-2026', 'ZZ_PLAN_2026', 2026, 'ZZBUD', '2026-05-31', 12);
-- The budget fact as gold_spread_budget builds it: two periods, one layer, both accounts.
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_spread_budget
  (scenario_id, cycle, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, dim_department, layer, currency, annual_amount, spread_profile_id, profile_name, period_weight, period_amount, submitted_by)
VALUES
  ('ZZ_PLAN_2026', 'ZZ-CY-2026', 'ZZE1', 2026, 6, 'ZZ1000', '', '', 'base', 'EUR', 150, 'manual', 'Manual (as-entered)', 0.6667, 100, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-2026', 'ZZE1', 2026, 6, 'ZZ4000', '', '', 'base', 'EUR', -150, 'manual', 'Manual (as-entered)', 0.6667, -100, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-2026', 'ZZE1', 2026, 7, 'ZZ1000', '', '', 'base', 'EUR', 150, 'manual', 'Manual (as-entered)', 0.3333, 50, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-2026', 'ZZE1', 2026, 7, 'ZZ4000', '', '', 'base', 'EUR', -150, 'manual', 'Manual (as-entered)', 0.3333, -50, '');
-- The actuals' world, P6 only, to document the defect this model fixes (not read by the model).
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZE1', 2026, 6, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 90, 0, 90, 1),
  ('ZZE1', 2026, 6, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 90, -90, 1);
INSERT INTO epm_gold.gold_entity_ownership
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, period_date, chain_depth, owner_group, has_complete_chain, outside_ownership_window, effective_ownership_pct, direct_ownership_pct, consolidation_method)
VALUES
  ('ZZG', 'ZZE1', 2026, 6, '2026-06-30', 1, 'ZZG', 1, 0, 1.0, 1.0, 'full');
