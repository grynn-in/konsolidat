-- gate: build gold_reporting_hierarchy gold_reporting_hierarchy_closure gold_tb_at_hierarchy_node assert_hierarchy_rollup_ties
-- gate: expect assert_hierarchy_rollup_ties pass
-- assert_hierarchy_rollup_ties, April-March fiscal year (konsolidat#171 step 2d, task 5b): must PASS when the
-- hierarchy TB model and the test both judge the tree at the DECLARED period end, not the last day of calendar month P.
--
-- The declared calendar is April-March: FY2026 P1 = 2025-04-01..2025-04-30 (the old calendar-month fallback for (2026, 1)
-- would say 2026-01-01, so toLastDayOfMonth of it is 2026-01-31, nine months late).
-- Hierarchy ZZ_AP over dim_business_unit, leaf ZZ_EX moves from ZZ_E to ZZ_B on 2026-01-01:
--   ZZ_ROOT group open | ZZ_E group .. 2025-12-31 | ZZ_B group open
--   ZZ_EX leaf under ZZ_E 2017-01-01 .. 2025-12-31 | ZZ_EX leaf under ZZ_B 2026-01-01 .. open
-- Entity ZZE1 posts 100 to ZZ1000 on ZZ_EX in FY2026 P1 (April 2025). On its declared end (2025-04-30) ZZ_EX
-- rolls to ZZ_E and ZZ_ROOT; on the calendar-month date (2026-01-31) it would roll to ZZ_B.
-- FY2026 P2 is NOT declared. The model used to give it the calendar-month date (the old fallback,
-- 2026-02-28, so ZZ_B) and the test now drops it; a period the calendar does not list has no date, so neither
-- side carries it (assert_trial_balance_period_declared, ERROR, names it). Red on the old model: ZZ_B group row
-- with no leaf row beside it.
ALTER TABLE epm_staging.reporting_hierarchies ADD COLUMN IF NOT EXISTS member_effective_from Date32 DEFAULT '1900-01-01';
ALTER TABLE epm_staging.reporting_hierarchies ADD COLUMN IF NOT EXISTS member_effective_to Date32 DEFAULT '2299-12-31';
INSERT INTO epm_staging.reporting_hierarchies
  (hierarchy_name, dimension, member_code, member_label, parent_member_code, is_group, hierarchy_level, path, effective_from, effective_to, is_default, status, member_effective_from, member_effective_to)
VALUES
  ('ZZ_AP', 'dim_business_unit', 'ZZ_ROOT', 'ZZ root', '', 1, 1, 'ZZ_ROOT', '', '', 1, 'Published', '2010-01-01', '2299-12-31'),
  ('ZZ_AP', 'dim_business_unit', 'ZZ_E', 'ZZ E', 'ZZ_ROOT', 1, 2, 'ZZ_ROOT/ZZ_E', '', '', 1, 'Published', '2010-01-01', '2025-12-31'),
  ('ZZ_AP', 'dim_business_unit', 'ZZ_B', 'ZZ B', 'ZZ_ROOT', 1, 2, 'ZZ_ROOT/ZZ_B', '', '', 1, 'Published', '2010-01-01', '2299-12-31'),
  ('ZZ_AP', 'dim_business_unit', 'ZZ_EX', 'ZZ EX', 'ZZ_E', 0, 3, 'ZZ_ROOT/ZZ_E/ZZ_EX', '', '', 1, 'Published', '2017-01-01', '2025-12-31'),
  ('ZZ_AP', 'dim_business_unit', 'ZZ_EX', 'ZZ EX', 'ZZ_B', 0, 3, 'ZZ_ROOT/ZZ_B/ZZ_EX', '', '', 1, 'Published', '2026-01-01', '2299-12-31');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Apr 2025', 'Regular', '2025-04-01', '2025-04-30', 'Q1', 'Open');
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, dim_business_unit, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZE1', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 'ZZ_EX', 100, 0, 100, 1),
  ('ZZE1', 2026, 2, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 'ZZ_EX', 50, 0, 50, 1);
