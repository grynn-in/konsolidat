-- gate: build gold_reporting_hierarchy gold_reporting_hierarchy_closure gold_tb_at_hierarchy_node gold_unassigned_hierarchy_members gold_budget_at_hierarchy_node gold_variance_at_hierarchy_node assert_hierarchy_node_period_declared
-- gate: expect assert_hierarchy_node_period_declared pass
-- konsolidat#189 PR3 (konsol#348, QA3 a): must PASS once the hierarchy-node models inner-join the declared
-- periods. The calendar declares FY2026 P1 only; the trial balance carries a row in FY2026 P5, which is
-- undeclared. Today the node model dates P5 at the last day of calendar May (the macro fallback) and emits
-- the row, so the test flags it; after the fix the period drops out and nothing is flagged.
--
-- The selector names the node models and this test only: gold_trial_balance and gold_spread_budget are
-- seeded (the build does not rebuild them), and assert_trial_balance_period_declared (ERROR, which this
-- same row also trips) is not selected, so it does not judge this fixture.
-- Hierarchy ZZ_PDH over dim_business_unit: ZZ_ROOT (group) with leaf ZZ_L, both open-ended.
-- Also named so they exist, empty: epm_gold.gold_spread_budget, epm_gold.gold_variance_analysis.
-- The live table may predate the two tranche columns: add them first. The seeded fact and variance clones may
-- predate cycle and currency (konsol#348 S3 B4, B8, B11), which the node models now read: add them too.
ALTER TABLE epm_staging.reporting_hierarchies ADD COLUMN IF NOT EXISTS member_effective_from Date32 DEFAULT '1900-01-01';
ALTER TABLE epm_staging.reporting_hierarchies ADD COLUMN IF NOT EXISTS member_effective_to Date32 DEFAULT '2299-12-31';
ALTER TABLE epm_staging.reporting_hierarchies MODIFY COLUMN member_effective_from Date32 DEFAULT '1900-01-01';
ALTER TABLE epm_staging.reporting_hierarchies MODIFY COLUMN member_effective_to Date32 DEFAULT '2299-12-31';
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS cycle String;
ALTER TABLE epm_gold.gold_spread_budget ADD COLUMN IF NOT EXISTS currency String;
ALTER TABLE epm_gold.gold_variance_analysis ADD COLUMN IF NOT EXISTS currency String;
INSERT INTO epm_staging.reporting_hierarchies
  (hierarchy_name, dimension, member_code, member_label, parent_member_code, is_group, hierarchy_level, path, effective_from, effective_to, is_default, status, member_effective_from, member_effective_to)
VALUES
  ('ZZ_PDH', 'dim_business_unit', 'ZZ_ROOT', 'ZZ root', '', 1, 1, 'ZZ_ROOT', '', '', 1, 'Published', '2010-01-01', '2299-12-31'),
  ('ZZ_PDH', 'dim_business_unit', 'ZZ_L', 'ZZ leaf', 'ZZ_ROOT', 0, 2, 'ZZ_ROOT/ZZ_L', '', '', 1, 'Published', '2010-01-01', '2299-12-31');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open');
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count, dim_business_unit)
VALUES
  ('ZZE1', 2026, 5, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 50, 0, 50, 1, 'ZZ_L');
