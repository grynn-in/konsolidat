-- gate: expect assert_budget_declared_historical_has_a_rate flag 2
-- assert_budget_declared_historical_has_a_rate (konsol#348 S4; #368 review, major): must FLAG
-- exactly 2 rows. A budget account declared fx_method = 'historical' whose Cycle's Rate Set holds
-- NO Historical Equity Rate tranche covering the period: consolidation_core's `case` then takes the
-- closing rate (`hr.historical_rate is not null` is false), and since the HER join is keyed on the
-- row's rate_set, a tranche recorded in the ACTUALS set does not count for a budget.
--
-- Test mode, seeded straight into the model's table: one EUR entity ZZE1 in a USD group ZZG,
-- 100% owned since 2020 (consolidation_ancestry / ownership_periods, so the test resolves the
-- owning group on the budget's own spine as the model does). The approved Cycle ZZ-CY-HER
-- (scenario ZZ_PLAN_2026) declares Rate Set ZZBUD. Rows of gold_consolidated_budget_tb:
--   ZZ3000 share capital, uses_historical_rate = 1, FY2026 P6 and P7   -- the two flagged rows
--   ZZ1000 cash,          uses_historical_rate = 0, FY2026 P6          -- never a candidate
-- Historical Equity Rates: ZZ3000's tranche exists ONLY in ZZACT (dated 2025-01-01, covering
-- both periods there). ZZBUD has none, so both budget periods are named:
--   (ZZ_PLAN_2026, ZZ-CY-HER, ZZBUD, ZZG, ZZE1, ZZ3000, USD, 2026, 6) and (..., 2026, 7).
-- The test reads these relations, seeded or empty: epm_gold.gold_consolidated_budget_tb,
-- epm_staging.fiscal_periods, epm_staging.budget_cycles, epm_staging.historical_equity_rates,
-- epm_staging.consolidation_ancestry, epm_staging.ownership_periods,
-- epm_staging.consolidation_method_declarations, epm_staging.business_disposals.
-- Budget dimensions at the fixture dims are dim_cost_center and dim_department; the live table may
-- have been built at other dims, so they are added by ALTER first.
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 6, 'FY2026-P06', 'Jun 2026', 'Regular', '2026-06-01', '2026-06-30', 'Q2', 'Open'),
  (2026, 7, 'FY2026-P07', 'Jul 2026', 'Regular', '2026-07-01', '2026-07-31', 'Q3', 'Open');
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZG', 'ZZE1', 'ZZG', 'ZZE1', 1, 1, 'ZZG/ZZE1', 'ZZG/ZZE1', 'ZZG', '');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id)
VALUES
  ('ZZG', 'ZZE1', '2020-01-01', '2149-06-06', 100, 'full', 'ZZG', '');
-- konsol#348 S4-Q7 (a): the one Rate Set flagged Is Actuals, and the budget's set.
INSERT INTO epm_staging.rate_sets
  (rate_set, label, is_actuals)
VALUES
  ('ZZACT', 'ZZ actuals', 1),
  ('ZZBUD', 'ZZ budget 2026', 0);
-- konsol#348 S4-Q2 (a): the approved Cycle, with the Rate Set it declares (BUD-3).
INSERT INTO epm_staging.budget_cycles
  (name, scenario_id, fiscal_year, rate_set, as_of_date, horizon_periods)
VALUES
  ('ZZ-CY-HER', 'ZZ_PLAN_2026', 2026, 'ZZBUD', '2026-05-31', 12);
-- The live rate table may predate konsol#374's to_currency and konsol#348's rate_set.
ALTER TABLE epm_staging.historical_equity_rates ADD COLUMN IF NOT EXISTS to_currency LowCardinality(String);
ALTER TABLE epm_staging.historical_equity_rates ADD COLUMN IF NOT EXISTS rate_set String;
INSERT INTO epm_staging.historical_equity_rates
  (consolidation_group, data_area_id, main_account, rate_date, historical_rate, to_currency, rate_set)
VALUES
  ('ZZG', 'ZZE1', 'ZZ3000', '2025-01-01', 1.30, 'USD', 'ZZACT');
-- The consolidated budget rows as the model would have built them: ZZ3000 at the CLOSING rate
-- (the silent fallback this test names), ZZ1000 at closing by declaration.
ALTER TABLE epm_gold.gold_consolidated_budget_tb ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_consolidated_budget_tb ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_consolidated_budget_tb
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name,
   dim_cost_center, dim_department, scenario_id, cycle, layer, local_amount,
   accounting_currency, reporting_currency, ownership_pct, consolidation_method,
   closing_rate, average_rate, translation_rate, uses_historical_rate, rate_set)
VALUES
  ('ZZG', 'ZZE1', 2026, 6, 'ZZ3000', 'ZZ share capital', '', '', 'ZZ_PLAN_2026', 'ZZ-CY-HER', 'base', -200.00, 'EUR', 'USD', 1, 'full', 1.10, 1.05, 1.10, 1, 'ZZBUD'),
  ('ZZG', 'ZZE1', 2026, 7, 'ZZ3000', 'ZZ share capital', '', '', 'ZZ_PLAN_2026', 'ZZ-CY-HER', 'base', -50.00, 'EUR', 'USD', 1, 'full', 1.20, 1.15, 1.20, 1, 'ZZBUD'),
  ('ZZG', 'ZZE1', 2026, 6, 'ZZ1000', 'ZZ cash', '', '', 'ZZ_PLAN_2026', 'ZZ-CY-HER', 'base', 200.00, 'EUR', 'USD', 1, 'full', 1.10, 1.05, 1.10, 0, 'ZZBUD');
