-- gate: expect assert_consolidated_budget_fact_hand_table flag 1
-- konsol#348 S6 WC1: the hand table can fail. gold_consolidated_budget_fact seeded straight into its
-- scratch table (test mode clones a view as a table) with the six expected rows of
-- assert_consolidated_budget_fact_hand_table.sql PLUS forecast round R1's row (-200), the undeclared
-- round a reader that ignored the Current Forecast would add. That row is produced and not expected:
-- 1 result (net -1).
INSERT INTO epm_gold.gold_consolidated_budget_fact
  (data_area_id, fiscal_year, fiscal_period, main_account, scenario_id, cycle, layer, consolidated_amount)
VALUES
  ('ZZG1', 2026, 1, 'ZZ4000', 'ZZ_PLAN_CBF', 'ZZ-CBF-B', 'base', -150),
  ('ZZG1', 2026, 1, 'CTA', 'ZZ_PLAN_CBF', 'ZZ-CBF-B', 'base', 2),
  ('ZZG1', 2026, 1, 'UNBALANCED', 'ZZ_PLAN_CBF', 'ZZ-CBF-B', 'base', 150),
  ('ZZG1', 2026, 1, 'ZZ4000', 'ZZ_PLAN_CBF', 'ZZ-CBF-B', 'challenge', -10),
  ('ZZG2', 2026, 1, 'ZZ4000', 'ZZ_PLAN_CBF', 'ZZ-CBF-B', 'base', -60),
  ('ZZG1', 2026, 1, 'ZZ4000', 'ZZ_FC_CBF', 'ZZ-CBF-R2', 'base', -220),
  ('ZZG1', 2026, 1, 'ZZ4000', 'ZZ_FC_CBF', 'ZZ-CBF-R1', 'base', -200);
