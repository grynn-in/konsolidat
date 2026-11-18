-- gate: expect assert_budget_translated_currency_has_a_governed_rate flag 1
-- assert_budget_translated_currency_has_a_governed_rate (konsol#348 S4 W5): must FLAG exactly 1 row.
-- The rows of the guard_refuses fixture, judged by the singular test instead of the pre_hook: the
-- approved Cycle ZZ-CY-2026 (Rate Set ZZBUD) budgets FY2026 P6 and P7 for a EUR entity in a USD
-- group; ZZBUD holds EUR->USD for P6 only, while the actuals set ZZACT holds both periods. The one
-- flagged row is (ZZ_PLAN_2026, ZZ-CY-2026, ZZBUD, EUR, USD, 2026, 7, 'missing'): the actuals set's
-- P7 rate is not read for a budget. P6 is not flagged.
-- Test mode: the test reads gold_spread_budget, silver_entity_currencies and these sources, seeded
-- or empty: epm_gold.gold_budget_entity_ownership (seeded: the ownership the model consolidates on),
-- epm_staging.budget_cycles, epm_staging.consolidation_ancestry,
-- epm_staging.ownership_periods, epm_staging.consolidation_method_declarations,
-- epm_staging.business_disposals, epm_staging.fiscal_periods, epm_gold.consolidation_groups,
-- epm_gold.currencies, epm_staging.group_exchange_rates.
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
-- The live rate table may predate konsol#348's rate_set: add it to the scratch clone first.
ALTER TABLE epm_staging.group_exchange_rates ADD COLUMN IF NOT EXISTS rate_set String;
-- The actuals set has P6 and P7; the budget's set has P6 only.
INSERT INTO epm_staging.group_exchange_rates
  (to_currency, from_currency, fiscal_year, fiscal_period, rate_type, rate, document, rate_set)
VALUES
  ('USD', 'EUR', 2026, 6, 'Closing', 1.00, 'ZZ-GER-2026-06', 'ZZACT'),
  ('USD', 'EUR', 2026, 6, 'Average', 1.00, 'ZZ-GER-2026-06', 'ZZACT'),
  ('USD', 'EUR', 2026, 7, 'Closing', 1.00, 'ZZ-GER-2026-07', 'ZZACT'),
  ('USD', 'EUR', 2026, 7, 'Average', 1.00, 'ZZ-GER-2026-07', 'ZZACT'),
  ('USD', 'EUR', 2026, 6, 'Closing', 1.10, 'ZZ-GER-2026-06-BUD', 'ZZBUD'),
  ('USD', 'EUR', 2026, 6, 'Average', 1.05, 'ZZ-GER-2026-06-BUD', 'ZZBUD');
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
-- konsolidat#369: the ownership the model consolidates on, as gold_budget_entity_ownership builds it
-- (test mode seeds the table the test reads; the resolution of the ancestry above gives these rows).
INSERT INTO epm_gold.gold_budget_entity_ownership
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, period_date, period_start_date, chain_depth, owner_group,
   has_complete_chain, outside_ownership_window, effective_ownership_pct, direct_ownership_pct, method_source, consolidation_method,
   path_count, direct_owner_count, has_partial_full_link)
VALUES
  ('ZZG', 'ZZE1', 2026, 6, '2026-06-30', '2026-06-01', 1, 'ZZG', 1, 0, 1.0, 1.0, 'link', 'full', 1, 1, 0),
  ('ZZG', 'ZZE1', 2026, 7, '2026-07-31', '2026-07-01', 1, 'ZZG', 1, 0, 1.0, 1.0, 'link', 'full', 1, 1, 0);
