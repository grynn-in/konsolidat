-- gate: expect assert_hierarchy_node_period_declared flag 2
-- konsolidat#189 PR3 (konsol#348, QA3 a; PR #360 review, finding 1): the test can fail. The node models
-- inner-join the same declared-period key set this test checks against, so a row they BUILD is declared by
-- construction and the plain fixture cannot distinguish a working test from one that cannot fail. Here two
-- node tables are seeded directly (test mode: nothing is rebuilt) with a row each in a period the calendar
-- does not declare, and the test must name both. This pins the test against a future model change that
-- lets an undeclared period through (a LEFT JOIN, a coalesce, a guessed date).
--
-- The calendar declares FY2026 P1 only. gold_tb_at_hierarchy_node carries a leaf row in FY2026 P5 and
-- gold_budget_at_hierarchy_node one in FY2026 P7: 2 results, one per (model, year, period).
-- gold_unassigned_hierarchy_members and gold_variance_at_hierarchy_node are read by the test and created
-- empty.
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open');
INSERT INTO epm_gold.gold_tb_at_hierarchy_node
  (hierarchy_name, hierarchy_dimension, hierarchy_member_code, hierarchy_member_label, hierarchy_level, hierarchy_is_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, dim_business_unit, dim_cost_center, dim_department, period_credit, period_debit, period_net_amount, transaction_count)
VALUES
  ('ZZ_PDH', 'dim_business_unit', 'ZZ_L', 'ZZ leaf', 2, 0, 'ZZE1', 2026, 5, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 'ZZ_L', '', '', 0, 50, 50, 1);
INSERT INTO epm_gold.gold_budget_at_hierarchy_node
  (hierarchy_name, hierarchy_dimension, hierarchy_member_code, hierarchy_member_label, hierarchy_level, hierarchy_is_group, scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, layer, period_amount, annual_amount)
VALUES
  ('ZZ_PDH', 'dim_business_unit', 'ZZ_L', 'ZZ leaf', 2, 0, 'ZZ_PLAN_2026', 'ZZE1', 2026, 7, 'ZZ4000', 'base', 70, 840);
