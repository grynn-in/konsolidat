-- gate: build gold_forecast_current_round gold_consolidated_budget_fact assert_consolidated_budget_fact_hand_table
-- gate: expect gold_consolidated_budget_fact built
-- gate: expect assert_consolidated_budget_fact_hand_table pass
-- konsol#348 S6 WC1 (S6-Q7 a): the consolidated budget fact, worked by hand. gold_fully_consolidated_budget
-- is seeded directly (its own fixtures prove its layers); the view is built over it and
-- gold_forecast_current_round, which is built from the declaration below.
--   Budget ZZ_PLAN_CBF, Cycle ZZ-CBF-B, FY2026 P1:
--     ZZG1 base: ZZE1 ZZ4000 -100 and ZZE2 ZZ4000 -50 (entity) -> -150; ZZE1 CTA 3 (cta) and CTA -1
--       (nci_attribution) -> 2; UNBALANCED 150 (unbalanced).
--     ZZG1 challenge: ZZE1 ZZ4000 -10 -> -10 (a layer of its own).
--     ZZG2 base: ZZE1 ZZ4000 -60 (a proportional holding; another group, never added to ZZG1).
--   Forecast ZZ_FC_CBF, FY2026: rounds ZZ-CBF-R1 (as of 2026-03-31) ZZG1 ZZE1 ZZ4000 -200 and ZZ-CBF-R2
--     (as of 2026-06-30) -220, both approved; the Current Forecast declares R2: the view holds -220,
--     never -420, and no R1 row.
-- Red before WC1: gold_consolidated_budget_fact does not exist (dbt parse fails on the test's ref).
-- Budget dimensions at the fixture dims are dim_cost_center and dim_department; the live table may have
-- been built at other dims, so they are added by ALTER first.
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ZZ_PLAN_CBF', 'ZZ plan', 'budget', 1),
  ('ZZ_FC_CBF', 'ZZ forecast', 'forecast', 1);
INSERT INTO epm_staging.budget_cycles
  (name, scenario_id, fiscal_year, rate_set, as_of_date, horizon_periods)
VALUES
  ('ZZ-CBF-B', 'ZZ_PLAN_CBF', 2026, 'ZZRS', DEFAULT, 0),
  ('ZZ-CBF-R1', 'ZZ_FC_CBF', 2026, 'ZZRS', '2026-03-31', 9),
  ('ZZ-CBF-R2', 'ZZ_FC_CBF', 2026, 'ZZRS', '2026-06-30', 6);
INSERT INTO epm_staging.current_forecasts
  (scenario_id, fiscal_year, cycle)
VALUES
  ('ZZ_FC_CBF', 2026, 'ZZ-CBF-R2');
ALTER TABLE epm_gold.gold_fully_consolidated_budget ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_fully_consolidated_budget ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_fully_consolidated_budget
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name,
   dim_cost_center, dim_department, scenario_id, cycle, layer, reporting_currency, amount, adjustment_type, journal_id)
VALUES
  ('ZZG1', 'ZZE1', 2026, 1, 'ZZ4000', 'ZZ revenue', '', '', 'ZZ_PLAN_CBF', 'ZZ-CBF-B', 'base', 'USD', -100, 'entity', ''),
  ('ZZG1', 'ZZE2', 2026, 1, 'ZZ4000', 'ZZ revenue', '', '', 'ZZ_PLAN_CBF', 'ZZ-CBF-B', 'base', 'USD', -50, 'entity', ''),
  ('ZZG1', 'ZZE1', 2026, 1, 'CTA', 'CTA', '', '', 'ZZ_PLAN_CBF', 'ZZ-CBF-B', 'base', 'USD', 3, 'cta', ''),
  ('ZZG1', 'ZZE1', 2026, 1, 'CTA', 'CTA', '', '', 'ZZ_PLAN_CBF', 'ZZ-CBF-B', 'base', 'USD', -1, 'nci_attribution', 'NCI-ZZG1-ZZE1-2026-P1-ZZ_PLAN_CBF-ZZ-CBF-B-base'),
  ('ZZG1', 'ZZE1', 2026, 1, 'UNBALANCED', 'Unbalanced budget', '', '', 'ZZ_PLAN_CBF', 'ZZ-CBF-B', 'base', 'USD', 150, 'unbalanced', ''),
  ('ZZG1', 'ZZE1', 2026, 1, 'ZZ4000', 'ZZ revenue', '', '', 'ZZ_PLAN_CBF', 'ZZ-CBF-B', 'challenge', 'USD', -10, 'entity', ''),
  ('ZZG2', 'ZZE1', 2026, 1, 'ZZ4000', 'ZZ revenue', '', '', 'ZZ_PLAN_CBF', 'ZZ-CBF-B', 'base', 'USD', -60, 'entity', ''),
  ('ZZG1', 'ZZE1', 2026, 1, 'ZZ4000', 'ZZ revenue', '', '', 'ZZ_FC_CBF', 'ZZ-CBF-R1', 'base', 'USD', -200, 'entity', ''),
  ('ZZG1', 'ZZE1', 2026, 1, 'ZZ4000', 'ZZ revenue', '', '', 'ZZ_FC_CBF', 'ZZ-CBF-R2', 'base', 'USD', -220, 'entity', '');
