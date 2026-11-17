-- gate: expect assert_budget_cycle_is_approved flag 1
-- assert_budget_cycle_is_approved (konsol#348 S4 W4, S4-Q2 a): must FLAG exactly 1 row.
-- Two Cycles of scenario ZZ_PLAN_2026 hold fact rows; only ZZ-CY-OK is approved (a row in
-- epm_staging.budget_cycles). ZZ-CY-DRAFT is not, so gold_consolidated_budget_tb leaves its rows
-- out, and this test names (ZZ_PLAN_2026, ZZ-CY-DRAFT) with its 2 fact rows. The approved Cycle is
-- not flagged.
-- Budget dimensions at the fixture dims are dim_cost_center and dim_department; a live
-- gold_spread_budget built at other dims gets them by ALTER first.
INSERT INTO epm_staging.budget_cycles
  (name, scenario_id, fiscal_year, rate_set, as_of_date, horizon_periods)
VALUES
  ('ZZ-CY-OK', 'ZZ_PLAN_2026', 2026, 'ZZBUD', '2026-05-31', 12);
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_spread_budget
  (scenario_id, cycle, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, dim_department, layer, currency, annual_amount, spread_profile_id, profile_name, period_weight, period_amount, submitted_by)
VALUES
  ('ZZ_PLAN_2026', 'ZZ-CY-OK', 'ZZE1', 2026, 6, 'ZZ4000', '', '', 'base', 'EUR', -100, 'manual', 'Manual (as-entered)', 1, -100, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-DRAFT', 'ZZE1', 2026, 6, 'ZZ4000', '', '', 'base', 'EUR', -120, 'manual', 'Manual (as-entered)', 1, -120, ''),
  ('ZZ_PLAN_2026', 'ZZ-CY-DRAFT', 'ZZE1', 2026, 7, 'ZZ4000', '', '', 'base', 'EUR', -120, 'manual', 'Manual (as-entered)', 1, -120, '');
