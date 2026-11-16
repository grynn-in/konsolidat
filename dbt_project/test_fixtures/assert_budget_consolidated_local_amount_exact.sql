-- gate: build gold_consolidated_budget_tb assert_budget_consolidated_local_amount_exact
-- gate: expect gold_consolidated_budget_tb built
-- gate: expect assert_budget_consolidated_local_amount_exact pass
-- assert_budget_consolidated_local_amount_exact (konsol#348 S4b live test, must fix): must PASS, and
-- the model must build. The consolidated budget's local_amount is the fact's period_amount ROUNDED
-- to 4 places, not truncated (konsolidat#191's class: toDecimal128(Float64) truncates toward zero;
-- repro `select toDecimal128(1234567.89, 4)` gives 1234567.8899).
--
-- One EUR entity ZZE1 in a USD group ZZG, 100% owned since 2020; the approved Cycle ZZ-CY-EXACT
-- (scenario ZZ_PLAN_2026, Rate Set ZZBUD) budgets FY2026 P6 and P7, one layer:
--   P6: ZZ1000 cash +1234567.89,          ZZ4000 revenue -1234567.89
--       expected local_amount  1234567.8900 and -1234567.8900   (truncation: 1234567.8899)
--   P7: ZZ1000 cash +83.33416666666667,   ZZ4000 revenue -83.33416666666667
--       (an annual 1000.01 spread evenly over 12 periods, as gold_spread_budget stores it)
--       expected local_amount  83.3342 and -83.3342             (truncation: 83.3341)
-- Red on toDecimal128(f.period_amount, 4): all four rows are flagged. Green on
-- cast_to_decimal128(): none.
-- Budget dimensions at the fixture dims are dim_cost_center and dim_department; a live
-- gold_spread_budget built at other dims gets them by ALTER first.
-- The model also reads these declared sources, empty here: epm_staging.historical_equity_rates,
-- epm_staging.consolidation_method_declarations, epm_staging.business_disposals.
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
  ('USD', 'EUR', 2026, 6, 'Average', 1.00, 'ZZ-GER-2026-06', 'ZZACT'),
  ('USD', 'EUR', 2026, 7, 'Closing', 1.00, 'ZZ-GER-2026-07', 'ZZACT'),
  ('USD', 'EUR', 2026, 7, 'Average', 1.00, 'ZZ-GER-2026-07', 'ZZACT');
-- konsol#348 S4-Q2 (a): the approved Cycle, with the Rate Set it declares (BUD-3).
INSERT INTO epm_staging.budget_cycles
  (name, scenario_id, fiscal_year, rate_set, as_of_date, horizon_periods)
VALUES
  ('ZZ-CY-EXACT', 'ZZ_PLAN_2026', 2026, 'ZZBUD', '2026-05-31', 12);
-- The budget fact as gold_spread_budget builds it: a cent value a double cannot hold exactly, and
-- a non-terminating spread.
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_spread_budget
  (scenario_id, cycle, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, dim_department, layer, currency, annual_amount, spread_profile_id, profile_name, period_weight, period_amount, submitted_by)
VALUES
  ('ZZ_PLAN_2026', 'ZZ-CY-EXACT', 'ZZE1', 2026, 6, 'ZZ1000', '', '', 'base', 'EUR', 1234567.89, 'manual', 'Manual (as-entered)', 1, 1234567.89, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-EXACT', 'ZZE1', 2026, 6, 'ZZ4000', '', '', 'base', 'EUR', -1234567.89, 'manual', 'Manual (as-entered)', 1, -1234567.89, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-EXACT', 'ZZE1', 2026, 7, 'ZZ1000', '', '', 'base', 'EUR', 1000.01, 'EVEN', 'Even', 0.08333333333333333, 83.33416666666667, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-EXACT', 'ZZE1', 2026, 7, 'ZZ4000', '', '', 'base', 'EUR', -1000.01, 'EVEN', 'Even', 0.08333333333333333, -83.33416666666667, '');
