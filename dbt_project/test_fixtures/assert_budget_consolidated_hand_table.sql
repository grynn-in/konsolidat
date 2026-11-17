-- gate: build gold_ownership_exits gold_budget_entity_ownership gold_consolidated_budget_tb assert_budget_consolidated_hand_table assert_budget_consolidated_periods_complete
-- gate: expect gold_consolidated_budget_tb built
-- gate: expect assert_budget_consolidated_hand_table pass
-- gate: expect assert_budget_consolidated_periods_complete pass
-- assert_budget_consolidated_hand_table (konsol#348 S4 W4): must PASS. Two Cycles on two Rate Sets,
-- two layers each, in one model: no telescoping across scenario, cycle or layer, and each Cycle
-- translates at ITS OWN set.
--
-- One EUR entity ZZE1 in a USD group ZZG, 100% owned since 2020. Scenario ZZ_PLAN_2026 has two
-- approved Cycles: ZZ-CY-HAND-A declares Rate Set ZZB1, ZZ-CY-HAND-B declares ZZB2. Each Cycle has
-- the layers base and challenge, and every (cycle, layer) holds the SAME local rows:
--   FY2026 P6: ZZ1000 cash +100, ZZ4000 revenue -100;  P7: ZZ1000 +50, ZZ4000 -50.
-- Rates EUR->USD (closing / average):
--   ZZB1   P6 1.10 / 1.05   P7 1.20 / 1.15
--   ZZB2   P6 2.00 / 1.90   P7 2.20 / 2.10
--   ZZACT  P6 1.00 / 1.00   P7 1.00 / 1.00   (the actuals set: never read for a budget)
-- The expected translated amounts are the test's hand table (tests/assert_budget_consolidated_hand_table.sql).
-- ZZ1000 is a closing-rate balance sheet key, so its P7 row carries a retranslation of
-- cum_local(100) x (C(P7) - C(P6)): 10 under ZZB1, 20 under ZZB2. Had any window in the core lost
-- the layer or the cycle, cum_local would be 200 or 400 there and the P7 cash row would be off by
-- that; had the rate key lost the set, each key would hold two Closing rates and the build would be
-- refused; had the budget read the actuals set, every amount would equal its local amount.
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
-- konsol#348 S4-Q7 (a): the one Rate Set flagged Is Actuals, and the two budget sets.
INSERT INTO epm_staging.rate_sets
  (rate_set, label, is_actuals)
VALUES
  ('ZZACT', 'ZZ actuals', 1),
  ('ZZB1', 'ZZ budget set 1', 0),
  ('ZZB2', 'ZZ budget set 2', 0);
-- The live rate tables may predate konsol#348's rate_set: add it to the scratch clones first.
ALTER TABLE epm_staging.group_exchange_rates ADD COLUMN IF NOT EXISTS rate_set String;
ALTER TABLE epm_staging.historical_equity_rates ADD COLUMN IF NOT EXISTS to_currency LowCardinality(String);
ALTER TABLE epm_staging.historical_equity_rates ADD COLUMN IF NOT EXISTS rate_set String;
INSERT INTO epm_staging.group_exchange_rates
  (to_currency, from_currency, fiscal_year, fiscal_period, rate_type, rate, document, rate_set)
VALUES
  ('USD', 'EUR', 2026, 6, 'Closing', 1.10, 'ZZ-GER-2026-06-B1', 'ZZB1'),
  ('USD', 'EUR', 2026, 6, 'Average', 1.05, 'ZZ-GER-2026-06-B1', 'ZZB1'),
  ('USD', 'EUR', 2026, 7, 'Closing', 1.20, 'ZZ-GER-2026-07-B1', 'ZZB1'),
  ('USD', 'EUR', 2026, 7, 'Average', 1.15, 'ZZ-GER-2026-07-B1', 'ZZB1'),
  ('USD', 'EUR', 2026, 6, 'Closing', 2.00, 'ZZ-GER-2026-06-B2', 'ZZB2'),
  ('USD', 'EUR', 2026, 6, 'Average', 1.90, 'ZZ-GER-2026-06-B2', 'ZZB2'),
  ('USD', 'EUR', 2026, 7, 'Closing', 2.20, 'ZZ-GER-2026-07-B2', 'ZZB2'),
  ('USD', 'EUR', 2026, 7, 'Average', 2.10, 'ZZ-GER-2026-07-B2', 'ZZB2'),
  ('USD', 'EUR', 2026, 6, 'Closing', 1.00, 'ZZ-GER-2026-06', 'ZZACT'),
  ('USD', 'EUR', 2026, 6, 'Average', 1.00, 'ZZ-GER-2026-06', 'ZZACT'),
  ('USD', 'EUR', 2026, 7, 'Closing', 1.00, 'ZZ-GER-2026-07', 'ZZACT'),
  ('USD', 'EUR', 2026, 7, 'Average', 1.00, 'ZZ-GER-2026-07', 'ZZACT');
-- konsol#348 S4-Q2 (a): two approved Cycles of one scenario, each declaring its own Rate Set.
INSERT INTO epm_staging.budget_cycles
  (name, scenario_id, fiscal_year, rate_set, as_of_date, horizon_periods)
VALUES
  ('ZZ-CY-HAND-A', 'ZZ_PLAN_2026', 2026, 'ZZB1', '2026-05-31', 12),
  ('ZZ-CY-HAND-B', 'ZZ_PLAN_2026', 2026, 'ZZB2', '2026-06-30', 12);
-- The same local rows under every (cycle, layer).
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_spread_budget
  (scenario_id, cycle, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, dim_department, layer, currency, annual_amount, spread_profile_id, profile_name, period_weight, period_amount, submitted_by)
VALUES
  ('ZZ_PLAN_2026', 'ZZ-CY-HAND-A', 'ZZE1', 2026, 6, 'ZZ1000', '', '', 'base', 'EUR', 150, 'manual', 'Manual (as-entered)', 0.6667, 100, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-HAND-A', 'ZZE1', 2026, 6, 'ZZ4000', '', '', 'base', 'EUR', -150, 'manual', 'Manual (as-entered)', 0.6667, -100, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-HAND-A', 'ZZE1', 2026, 7, 'ZZ1000', '', '', 'base', 'EUR', 150, 'manual', 'Manual (as-entered)', 0.3333, 50, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-HAND-A', 'ZZE1', 2026, 7, 'ZZ4000', '', '', 'base', 'EUR', -150, 'manual', 'Manual (as-entered)', 0.3333, -50, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-HAND-A', 'ZZE1', 2026, 6, 'ZZ1000', '', '', 'challenge', 'EUR', 150, 'manual', 'Manual (as-entered)', 0.6667, 100, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-HAND-A', 'ZZE1', 2026, 6, 'ZZ4000', '', '', 'challenge', 'EUR', -150, 'manual', 'Manual (as-entered)', 0.6667, -100, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-HAND-A', 'ZZE1', 2026, 7, 'ZZ1000', '', '', 'challenge', 'EUR', 150, 'manual', 'Manual (as-entered)', 0.3333, 50, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-HAND-A', 'ZZE1', 2026, 7, 'ZZ4000', '', '', 'challenge', 'EUR', -150, 'manual', 'Manual (as-entered)', 0.3333, -50, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-HAND-B', 'ZZE1', 2026, 6, 'ZZ1000', '', '', 'base', 'EUR', 150, 'manual', 'Manual (as-entered)', 0.6667, 100, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-HAND-B', 'ZZE1', 2026, 6, 'ZZ4000', '', '', 'base', 'EUR', -150, 'manual', 'Manual (as-entered)', 0.6667, -100, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-HAND-B', 'ZZE1', 2026, 7, 'ZZ1000', '', '', 'base', 'EUR', 150, 'manual', 'Manual (as-entered)', 0.3333, 50, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-HAND-B', 'ZZE1', 2026, 7, 'ZZ4000', '', '', 'base', 'EUR', -150, 'manual', 'Manual (as-entered)', 0.3333, -50, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-HAND-B', 'ZZE1', 2026, 6, 'ZZ1000', '', '', 'challenge', 'EUR', 150, 'manual', 'Manual (as-entered)', 0.6667, 100, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-HAND-B', 'ZZE1', 2026, 6, 'ZZ4000', '', '', 'challenge', 'EUR', -150, 'manual', 'Manual (as-entered)', 0.6667, -100, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-HAND-B', 'ZZE1', 2026, 7, 'ZZ1000', '', '', 'challenge', 'EUR', 150, 'manual', 'Manual (as-entered)', 0.3333, 50, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-HAND-B', 'ZZE1', 2026, 7, 'ZZ4000', '', '', 'challenge', 'EUR', -150, 'manual', 'Manual (as-entered)', 0.3333, -50, '');
