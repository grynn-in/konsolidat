-- gate: build gold_reporting_hierarchy gold_reporting_hierarchy_closure gold_variance_at_hierarchy_node gold_budget_at_hierarchy_node gold_unassigned_hierarchy_members assert_variance_node_single_budget
-- gate: expect assert_variance_node_single_budget pass
-- gate: expect gold_budget_at_hierarchy_node built
-- gate: expect gold_unassigned_hierarchy_members built
-- assert_variance_node_single_budget, April-March fiscal year (konsolidat#171 step 2d, task 5c): must PASS when the
-- variance, budget and unassigned-member models and the test all judge the tree at the DECLARED period end.
--
-- The declared calendar is April-March: FY2026 P1 = 2025-04-01..2025-04-30 (the old calendar-month fallback for (2026, 1)
-- would say 2026-01-01, nine months late). Hierarchy ZZ_AP over dim_cost_center, leaf ZZ_EX moves from ZZ_E to
-- ZZ_B on 2026-01-01. FY2026 P1 (declared end 2025-04-30) rolls ZZ_EX to ZZ_E; the calendar-month date would roll it to ZZ_B.
-- FY2026 P2 is NOT declared. The models used to give it the calendar-month date (2026-02-28, so ZZ_B); now it has
-- no date and is dropped, and the test drops it too. Red on the old models: a ZZ_B leaf row the test does not expect.
ALTER TABLE epm_staging.reporting_hierarchies ADD COLUMN IF NOT EXISTS member_effective_from Date32 DEFAULT '1900-01-01';
ALTER TABLE epm_staging.reporting_hierarchies ADD COLUMN IF NOT EXISTS member_effective_to Date32 DEFAULT '2299-12-31';
INSERT INTO epm_staging.reporting_hierarchies
  (hierarchy_name, dimension, member_code, member_label, parent_member_code, is_group, hierarchy_level, path, effective_from, effective_to, is_default, status, member_effective_from, member_effective_to)
VALUES
  ('ZZ_AP', 'dim_cost_center', 'ZZ_ROOT', 'ZZ root', '', 1, 1, 'ZZ_ROOT', '', '', 1, 'Published', '2010-01-01', '2299-12-31'),
  ('ZZ_AP', 'dim_cost_center', 'ZZ_E', 'ZZ E', 'ZZ_ROOT', 1, 2, 'ZZ_ROOT/ZZ_E', '', '', 1, 'Published', '2010-01-01', '2025-12-31'),
  ('ZZ_AP', 'dim_cost_center', 'ZZ_B', 'ZZ B', 'ZZ_ROOT', 1, 2, 'ZZ_ROOT/ZZ_B', '', '', 1, 'Published', '2010-01-01', '2299-12-31'),
  ('ZZ_AP', 'dim_cost_center', 'ZZ_EX', 'ZZ EX', 'ZZ_E', 0, 3, 'ZZ_ROOT/ZZ_E/ZZ_EX', '', '', 1, 'Published', '2017-01-01', '2025-12-31'),
  ('ZZ_AP', 'dim_cost_center', 'ZZ_EX', 'ZZ EX', 'ZZ_B', 0, 3, 'ZZ_ROOT/ZZ_B/ZZ_EX', '', '', 1, 'Published', '2026-01-01', '2299-12-31');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Apr 2025', 'Regular', '2025-04-01', '2025-04-30', 'Q1', 'Open');
INSERT INTO epm_gold.gold_variance_analysis
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_pnl,
   dim_cost_center, dim_department, actual_amount, budget_amount, variance_abs, variance_pct, variance_favorable,
   budget_scenario_id)
VALUES
  ('ZZE1', 2026, 1, 'ZZ4000', 'revenue', 'Revenue', 1, 'ZZ_EX', '', 100, 90, 10, NULL, NULL, 'BUDGET'),
  ('ZZE1', 2026, 2, 'ZZ4000', 'revenue', 'Revenue', 1, 'ZZ_EX', '', 50, 40, 10, NULL, NULL, 'BUDGET');
INSERT INTO epm_gold.gold_spread_budget
  (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, dim_department, layer, period_amount, annual_amount)
VALUES
  ('ZZ_PLAN', 'ZZE1', 2026, 1, 'ZZ4000', 'ZZ_EX', '', 'base', 90, 1200),
  ('ZZ_PLAN', 'ZZE1', 2026, 2, 'ZZ4000', 'ZZ_EX', '', 'base', 40, 1200);
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, dim_cost_center, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZE1', 2026, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 'ZZ_EX', 100, 0, 100, 1),
  ('ZZE1', 2026, 2, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 'ZZ_EX', 50, 0, 50, 1);
