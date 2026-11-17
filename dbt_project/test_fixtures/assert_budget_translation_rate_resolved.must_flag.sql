-- gate: expect assert_budget_translation_rate_resolved flag 2
-- assert_budget_translation_rate_resolved (konsol#348 S4 W8): must FLAG exactly 2 rows.
-- Every row of gold_consolidated_budget_tb must carry a resolved translation rate, as every row of
-- gold_consolidated_trial_balance must (assert_translation_rate_resolved). Seeded straight into
-- the model's table (test mode), the two ways a rate escapes:
--   ZZZ0: a cross-currency row whose translation_rate collapsed to 0 (a join miss under
--         join_use_nulls=0), so its translated amounts are 0;
--   ZZNL: a cross-currency row whose translation_rate is NULL (escaped every rate branch; the
--         core's throwIf should have stopped the build).
-- A third row, ZZOK, translated at 1.1 in the Cycle's set, is not flagged; nor would a
-- cross-currency row at exactly 1.0 be (a legitimate approved quote, konsolidat#194).
-- Budget dimensions at the fixture dims are dim_cost_center and dim_department; the live table may
-- have been built at other dims, so they are added by ALTER first.
ALTER TABLE epm_gold.gold_consolidated_budget_tb ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_consolidated_budget_tb ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_consolidated_budget_tb
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name,
   dim_cost_center, dim_department, scenario_id, cycle, layer, local_amount,
   accounting_currency, reporting_currency, ownership_pct, consolidation_method,
   closing_rate, average_rate, translation_rate, rate_set)
VALUES
  ('ZZG', 'ZZZ0', 2026, 6, 'ZZ1000', 'ZZ cash', '', '', 'ZZ_PLAN_2026', 'ZZ-CY-RATE', 'base', 100.00, 'EUR', 'USD', 1, 'full', 0, 0, 0, 'ZZBUD'),
  ('ZZG', 'ZZNL', 2026, 6, 'ZZ1000', 'ZZ cash', '', '', 'ZZ_PLAN_2026', 'ZZ-CY-RATE', 'base', 100.00, 'EUR', 'USD', 1, 'full', 1.2, 1.1, NULL, 'ZZBUD'),
  ('ZZG', 'ZZOK', 2026, 6, 'ZZ1000', 'ZZ cash', '', '', 'ZZ_PLAN_2026', 'ZZ-CY-RATE', 'base', 100.00, 'EUR', 'USD', 1, 'full', 1.1, 1.05, 1.1, 'ZZBUD');
