-- gate: build gold_reporting_hierarchy gold_reporting_hierarchy_closure assert_hierarchy_rollup_ties
-- gate: expect assert_hierarchy_rollup_ties pass
-- konsolidat#189 PR3 (konsol#348, A6): the rollup test dates a period by the declared calendar only, as the
-- node models do since A2 (QA3 a). It must PASS. Before A6 it FAILED with 2 rows: a period the calendar
-- does not declare was dated at the last day of the calendar month its number names
-- (build_date_from_year_period), and its leaf counted towards whatever groups held on that invented date.
--
-- The calendar is an April fiscal year: FY2026 P1 is April 2025, P2 May 2025. P10 is not declared.
-- Hierarchy ZZ_RT over dim_business_unit: ZZ_ROOT and ZZ_E and ZZ_B (groups, open-ended); leaf ZZ_X under ZZ_E
-- 2010-01-01 .. 2025-12-31, then under ZZ_B from 2026-01-01.
--
-- gold_tb_at_hierarchy_node is seeded (the selector does not rebuild it):
--   FY2026 P1 (declared end 2025-04-30): ZZ_X 100, ZZ_E 100, ZZ_ROOT 100. On the declared date ZZ_X sits under
--     ZZ_E, so the groups tie. The macro would have dated P1 at 2026-01-31, under ZZ_B: the declared date is the
--     one read, before and after A6.
--   FY2026 P10 (undeclared): leaf ZZ_X 30, no group row. Before A6 the test dated it 2026-10-31 and expected 30
--     at ZZ_B and ZZ_ROOT (2 rows). Now the period is not judged here; assert_hierarchy_node_period_declared
--     names it.
-- The live table may predate the two tranche columns: add them first.
ALTER TABLE epm_staging.reporting_hierarchies ADD COLUMN IF NOT EXISTS member_effective_from Date32 DEFAULT '1900-01-01';
ALTER TABLE epm_staging.reporting_hierarchies ADD COLUMN IF NOT EXISTS member_effective_to Date32 DEFAULT '2299-12-31';
ALTER TABLE epm_staging.reporting_hierarchies MODIFY COLUMN member_effective_from Date32 DEFAULT '1900-01-01';
ALTER TABLE epm_staging.reporting_hierarchies MODIFY COLUMN member_effective_to Date32 DEFAULT '2299-12-31';
INSERT INTO epm_staging.reporting_hierarchies
  (hierarchy_name, dimension, member_code, member_label, parent_member_code, is_group, hierarchy_level, path, effective_from, effective_to, is_default, status, member_effective_from, member_effective_to)
VALUES
  ('ZZ_RT', 'dim_business_unit', 'ZZ_ROOT', 'ZZ root', '', 1, 1, 'ZZ_ROOT', '', '', 1, 'Published', '2010-01-01', '2299-12-31'),
  ('ZZ_RT', 'dim_business_unit', 'ZZ_E', 'ZZ E', 'ZZ_ROOT', 1, 2, 'ZZ_ROOT/ZZ_E', '', '', 1, 'Published', '2010-01-01', '2299-12-31'),
  ('ZZ_RT', 'dim_business_unit', 'ZZ_B', 'ZZ B', 'ZZ_ROOT', 1, 2, 'ZZ_ROOT/ZZ_B', '', '', 1, 'Published', '2010-01-01', '2299-12-31'),
  ('ZZ_RT', 'dim_business_unit', 'ZZ_X', 'ZZ X', 'ZZ_E', 0, 3, 'ZZ_ROOT/ZZ_E/ZZ_X', '', '', 1, 'Published', '2010-01-01', '2025-12-31'),
  ('ZZ_RT', 'dim_business_unit', 'ZZ_X', 'ZZ X', 'ZZ_B', 0, 3, 'ZZ_ROOT/ZZ_B/ZZ_X', '', '', 1, 'Published', '2026-01-01', '2299-12-31');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Apr 2025', 'Regular', '2025-04-01', '2025-04-30', 'Q1', 'Open'),
  (2026, 2, 'FY2026-P02', 'May 2025', 'Regular', '2025-05-01', '2025-05-31', 'Q1', 'Open');
INSERT INTO epm_gold.gold_tb_at_hierarchy_node
  (hierarchy_name, hierarchy_dimension, hierarchy_member_code, hierarchy_member_label, hierarchy_level, hierarchy_is_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, dim_business_unit, dim_cost_center, dim_department, period_credit, period_debit, period_net_amount, transaction_count)
VALUES
  ('ZZ_RT', 'dim_business_unit', 'ZZ_X', 'ZZ X', 3, 0, 'ZZE1', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, '', '', '', 0, 100, 100, 1),
  ('ZZ_RT', 'dim_business_unit', 'ZZ_E', 'ZZ E', 2, 1, 'ZZE1', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, '', '', '', 0, 100, 100, 1),
  ('ZZ_RT', 'dim_business_unit', 'ZZ_ROOT', 'ZZ root', 1, 1, 'ZZE1', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, '', '', '', 0, 100, 100, 1),
  ('ZZ_RT', 'dim_business_unit', 'ZZ_X', 'ZZ X', 3, 0, 'ZZE1', 2026, 10, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, '', '', '', 0, 30, 30, 1);
