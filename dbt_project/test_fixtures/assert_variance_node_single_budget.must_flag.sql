-- assert_variance_node_single_budget: must FAIL with exactly 3 results (konsolidat#249).
--
-- gold_variance_analysis has three leaf rows under cost-centre ZZCC1 of hierarchy ZZH.
-- ZZ4000: the node row is there, but its budget is 80 against the analysis' 90.
-- ZZ5000: the node has NO row at all. The test meets it through a FULL OUTER JOIN, where
--         under join_use_nulls = 0 the missing side's String key is '' and not NULL; the
--         test reads it as coalesce(n.node_hierarchy, '') = '', which holds either way,
--         so ZZ5000 must be flagged.
-- ZZ6000: the node has no row either, and the analysis row is 0 actual with no budget, so
--         no amount differs: only the missing-key clause can flag it. A test that read
--         `n.node_hierarchy is null` would report ZZ4000 and ZZ5000 and miss ZZ6000.
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open');
INSERT INTO epm_gold.gold_reporting_hierarchy
  (hierarchy_name, dimension, member_code, member_label, parent_member_code, is_group, hierarchy_level, path,
   effective_from, effective_to, is_default, member_effective_from, member_effective_to)
VALUES
  ('ZZH', 'dim_cost_center', 'ZZCCG', 'ZZ all', '', 1, 0, 'ZZCCG', '', '', 1, '1900-01-01', '2299-12-31'),
  ('ZZH', 'dim_cost_center', 'ZZCC1', 'ZZ one', 'ZZCCG', 0, 1, 'ZZCCG/ZZCC1', '', '', 1, '1900-01-01', '2299-12-31');
INSERT INTO epm_gold.gold_variance_analysis
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_pnl,
   dim_cost_center, dim_department, actual_amount, budget_amount, variance_abs, variance_pct, variance_favorable,
   budget_scenario_id)
VALUES
  ('ZZE1', 2026, 1, 'ZZ4000', 'revenue', 'Revenue', 1, 'ZZCC1', '', 100, 90, 10, NULL, NULL, 'BUDGET'),
  ('ZZE1', 2026, 1, 'ZZ5000', 'costs', 'Expense', 1, 'ZZCC1', '', 50, NULL, 50, NULL, NULL, 'BUDGET'),
  ('ZZE1', 2026, 1, 'ZZ6000', 'other costs', 'Expense', 1, 'ZZCC1', '', 0, NULL, 0, NULL, NULL, 'BUDGET');
INSERT INTO epm_gold.gold_variance_at_hierarchy_node
  (hierarchy_name, hierarchy_dimension, hierarchy_member_code, hierarchy_member_label, hierarchy_level,
   hierarchy_is_group, data_area_id, fiscal_year, fiscal_period, main_account, budget_scenario_id,
   dim_cost_center, dim_department, actual_amount, budget_amount, variance_abs)
VALUES
  ('ZZH', 'dim_cost_center', 'ZZCC1', 'ZZ one', 1, 0, 'ZZE1', 2026, 1, 'ZZ4000', 'BUDGET', 'ZZCC1', '', 100, 80, 20);
