-- gate: build gold_consolidated_budget_tb gold_fully_consolidated_budget assert_budget_consolidated_balances assert_budget_consolidated_plugs_hand_table assert_budget_consolidated_grain_unique assert_budget_translation_rate_resolved
-- gate: expect gold_fully_consolidated_budget built
-- gate: expect assert_budget_consolidated_balances pass
-- gate: expect assert_budget_consolidated_plugs_hand_table pass
-- gate: expect assert_budget_consolidated_grain_unique pass
-- gate: expect assert_budget_translation_rate_resolved pass
-- assert_budget_consolidated_balances (konsol#348 S4 W6): must PASS, and both budget models must
-- build. The fully consolidated budget's layers (entity, unbalanced, cta, nci_attribution) sum to 0
-- per (group, scenario, cycle, layer, entity, period) for a two-currency, partly owned entity. The
-- W8 grain and rate tests must pass on the same built rows (one row per key; every row rated).
-- S4-Q8 (b): these rows are double-entry (L = 0 in every consolidation), so the 'unbalanced' layer
-- is 0 throughout and 'cta' is exactly the whole residual it was before the split; the plug hand
-- table (tests/assert_budget_consolidated_plugs_hand_table.sql) pins both.
--
-- One EUR entity ZZE1 in a USD group ZZG, 80% owned (full method) since 2020; the group's root
-- declares nci_account ZZ3500 and the chart flags ZZ3000 as retained earnings. The approved Cycle
-- ZZ-CY-BAL (scenario ZZ_PLAN_2026, Rate Set ZZBUD) budgets FY2026 P6 and P7 in two layers with
-- DIFFERENT local rows, so a CTA or an NCI share computed across layers would not balance:
--   base       P6: ZZ1000 cash +100, ZZ4000 revenue -100;   P7: ZZ1000 +50, ZZ4000 -50
--   challenge  P6: ZZ1000 cash +40,  ZZ4000 revenue -40
-- Rates EUR->USD (closing / average): ZZBUD P6 1.10 / 1.05, P7 1.20 / 1.15; ZZACT (the actuals
-- set, never read for a budget) 1.00 / 1.00 in both periods.
--
-- Hand values (group currency USD), to read against the built table:
--   base P6:  entity 110 (cash) and -105 (revenue), sum 5; cta -5;
--             nci_attribution: result_share = -105 x 0.2 = -21, cta_share = 0.2 x -5 = -1,
--             lines ZZ3000 +21, CTA +1, ZZ3500 -22.                        Total 0.
--   base P7:  entity 70 (50 x 1.20 + retranslation 100 x (1.20 - 1.10)) and -57.5, sum 12.5;
--             cta -12.5; nci: result -11.5, cta_share -2.5; lines ZZ3000 +11.5, CTA +2.5,
--             ZZ3500 -14.                                                    Total 0.
--   challenge P6: entity 44 and -42, sum 2; cta -2; nci: result -8.4, cta_share -0.4;
--             lines ZZ3000 +8.4, CTA +0.4, ZZ3500 -8.8.                      Total 0.
-- Had the CTA been summed over both layers at P6 it would be -7 under each, and neither layer
-- would balance. Red before W6: the test refers to a model that does not exist.
-- Budget dimensions at the fixture dims are dim_cost_center and dim_department; a live
-- gold_spread_budget built at other dims gets them by ALTER first.
-- The models also read these declared sources, empty here: epm_staging.historical_equity_rates,
-- epm_staging.consolidation_method_declarations, epm_staging.business_disposals.
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, is_equity, fx_method, is_posting, is_retained_earnings, uses_historical_rate)
VALUES
  ('ZZ1000', 'ZZ cash', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ3000', 'ZZ retained earnings', 'Equity', 'Equity', 0, 1, 1, 'closing', 1, 1, 0),
  ('ZZ3500', 'ZZ non-controlling interest', 'Equity', 'Equity', 0, 1, 1, 'closing', 1, 0, 0),
  ('ZZ4000', 'ZZ revenue', 'Revenue', 'Revenue', 1, 0, 0, 'average', 1, 0, 0);
INSERT INTO epm_silver.silver_entity_currencies
  (data_area_id, accounting_currency)
VALUES
  ('ZZE1', 'EUR');
-- The live groups table may predate konsol#202's nci_account: add it to the scratch clone first.
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS nci_account String DEFAULT '';
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency, nci_account)
VALUES
  ('ZZG', '', 'ZZ Group', 'USD', 'ZZ3500'),
  ('ZZG', 'ZZE1', 'ZZ Entity 1', 'USD', '');
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZG', 'ZZE1', 'ZZG', 'ZZE1', 1, 1, 'ZZG/ZZE1', 'ZZG/ZZE1', 'ZZG', '');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id)
VALUES
  ('ZZG', 'ZZE1', '2020-01-01', '2149-06-06', 80, 'full', 'ZZG', '');
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
  ('ZZ-CY-BAL', 'ZZ_PLAN_2026', 2026, 'ZZBUD', '2026-05-31', 12);
-- The budget fact as gold_spread_budget builds it: two layers with different rows.
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_spread_budget
  (scenario_id, cycle, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, dim_department, layer, currency, annual_amount, spread_profile_id, profile_name, period_weight, period_amount, submitted_by)
VALUES
  ('ZZ_PLAN_2026', 'ZZ-CY-BAL', 'ZZE1', 2026, 6, 'ZZ1000', '', '', 'base', 'EUR', 150, 'manual', 'Manual (as-entered)', 0.6667, 100, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-BAL', 'ZZE1', 2026, 6, 'ZZ4000', '', '', 'base', 'EUR', -150, 'manual', 'Manual (as-entered)', 0.6667, -100, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-BAL', 'ZZE1', 2026, 7, 'ZZ1000', '', '', 'base', 'EUR', 150, 'manual', 'Manual (as-entered)', 0.3333, 50, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-BAL', 'ZZE1', 2026, 7, 'ZZ4000', '', '', 'base', 'EUR', -150, 'manual', 'Manual (as-entered)', 0.3333, -50, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-BAL', 'ZZE1', 2026, 6, 'ZZ1000', '', '', 'challenge', 'EUR', 40, 'manual', 'Manual (as-entered)', 1, 40, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-BAL', 'ZZE1', 2026, 6, 'ZZ4000', '', '', 'challenge', 'EUR', -40, 'manual', 'Manual (as-entered)', 1, -40, '');
