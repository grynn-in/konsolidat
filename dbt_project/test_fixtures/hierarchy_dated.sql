-- gate: build +assert_hierarchy_closure_windows +assert_hierarchy_node_as_of +assert_unassigned_as_of
-- gate: expect assert_hierarchy_closure_windows pass
-- gate: expect assert_hierarchy_node_as_of pass
-- gate: expect assert_unassigned_as_of pass
-- konsolidat#220: a reporting hierarchy whose members are dated. A member row is one tranche of a code, valid
-- from member_effective_from to member_effective_to (open = 2299-12-31); a renamed, moved or ended node is a
-- second tranche of the same code. The closure and every node model must resolve the tree as it was in a period.
--
-- Hierarchy ZZ_DIV over dim_business_unit:
--   ZZ_ROOT group 2010-01-01 .. open
--   ZZ_A    group 2010-01-01 .. 2024-12-31 "Alpha"      } a rename: two tranches of one code
--   ZZ_A    group 2025-01-01 .. open       "Alpha New"  }
--   ZZ_B    group 2010-01-01 .. open
--   ZZ_E    group 2017-01-01 .. 2024-12-31               (ended)
--   ZZ_G    group 2013-04-01 .. 2020-06-03               (disposed)
--   ZZ_EX   leaf under ZZ_E 2017-01-01 .. 2024-12-31    } a move: two tranches of one code
--   ZZ_EX   leaf under ZZ_B 2025-01-01 .. open          }
--   ZZ_GX   leaf under ZZ_G 2013-04-01 .. 2020-06-03
--   ZZ_AX   leaf under ZZ_A 2010-01-01 .. open
--
-- The live table may predate the two tranche columns: add them first.
ALTER TABLE epm_staging.reporting_hierarchies ADD COLUMN IF NOT EXISTS member_effective_from Date32 DEFAULT '1900-01-01';
ALTER TABLE epm_staging.reporting_hierarchies ADD COLUMN IF NOT EXISTS member_effective_to Date32 DEFAULT '2299-12-31';
-- A table that already has them as plain Date (1970-01-01..2149-06-06 clamps both ends) becomes Date32.
ALTER TABLE epm_staging.reporting_hierarchies MODIFY COLUMN member_effective_from Date32 DEFAULT '1900-01-01';
ALTER TABLE epm_staging.reporting_hierarchies MODIFY COLUMN member_effective_to Date32 DEFAULT '2299-12-31';
-- konsol#287: the budget input tables name no dimension; konsol adds the site's
-- declared ones. These rows carry dim_cost_center and dim_department, so the
-- columns are added first, for a stack whose site declares neither.
INSERT INTO epm_staging.reporting_hierarchies
  (hierarchy_name, dimension, member_code, member_label, parent_member_code, is_group, hierarchy_level, path, effective_from, effective_to, is_default, status, member_effective_from, member_effective_to)
VALUES
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_ROOT', 'ZZ root', '', 1, 1, 'ZZ_ROOT', '', '', 1, 'Published', '2010-01-01', '2299-12-31'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_A', 'Alpha', 'ZZ_ROOT', 1, 2, 'ZZ_ROOT/ZZ_A', '', '', 1, 'Published', '2010-01-01', '2024-12-31'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_A', 'Alpha New', 'ZZ_ROOT', 1, 2, 'ZZ_ROOT/ZZ_A', '', '', 1, 'Published', '2025-01-01', '2299-12-31'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_B', 'ZZ B', 'ZZ_ROOT', 1, 2, 'ZZ_ROOT/ZZ_B', '', '', 1, 'Published', '2010-01-01', '2299-12-31'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_E', 'ZZ E', 'ZZ_ROOT', 1, 2, 'ZZ_ROOT/ZZ_E', '', '', 1, 'Published', '2017-01-01', '2024-12-31'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_G', 'ZZ G', 'ZZ_ROOT', 1, 2, 'ZZ_ROOT/ZZ_G', '', '', 1, 'Published', '2013-04-01', '2020-06-03'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_EX', 'ZZ EX', 'ZZ_E', 0, 3, 'ZZ_ROOT/ZZ_E/ZZ_EX', '', '', 1, 'Published', '2017-01-01', '2024-12-31'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_EX', 'ZZ EX', 'ZZ_B', 0, 3, 'ZZ_ROOT/ZZ_B/ZZ_EX', '', '', 1, 'Published', '2025-01-01', '2299-12-31'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_GX', 'ZZ GX', 'ZZ_G', 0, 3, 'ZZ_ROOT/ZZ_G/ZZ_GX', '', '', 1, 'Published', '2013-04-01', '2020-06-03'),
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_AX', 'ZZ AX', 'ZZ_A', 0, 3, 'ZZ_ROOT/ZZ_A/ZZ_AX', '', '', 1, 'Published', '2010-01-01', '2299-12-31');
--
-- Actuals (row H3), entity ZZE1, one balanced voucher each: ZZ1000 cash Dr | ZZ4000 revenue Cr, business unit on
-- both lines. FY = calendar year, P6 = June (epm_staging.fiscal_periods gives each period's end_date):
--   ZZ_EX FY2018 P6 100 | ZZ_GX FY2018 P6 20 | ZZ_AX FY2024 P6 3 | ZZ_EX FY2025 P6 500 | ZZ_AX FY2025 P6 4000
-- So on ZZ1000: FY2018 ZZ_E 100, ZZ_G 20, ZZ_ROOT 120, no ZZ_B; FY2024 ZZ_A "Alpha" 3; FY2025 ZZ_B 500,
-- ZZ_A "Alpha New" 4000, ZZ_ROOT 4500, no ZZ_E or ZZ_G.
--
-- Where the dimensioned rows enter: trial-balance submissions carry the declared dimensions (konsol#255),
-- one Period movement batch per period (epm_raw.trial_balance_submissions + its control row). Until
-- konsol#348 (PR3, A12) the rows were seeded in bronze_general_journal_account_entries, the ERP branch of
-- silver_gl_entries, which that change removed.
--
-- The lineage of gold_trial_balance reads these tables too, empty here, so they are named to exist:
-- epm_staging.dimension_mappings.
--
-- The live submission tables and chart may predate their partner, basis and retained-earnings columns: add them first.
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS partner_data_area_id String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS dim_business_unit String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS dim_cost_center String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS dim_department String DEFAULT '';
ALTER TABLE epm_staging.main_accounts ADD COLUMN IF NOT EXISTS is_retained_earnings UInt8 DEFAULT 0;
INSERT INTO epm_staging.main_accounts
  (main_account, account_name, chart_of_accounts, parent_account, is_group, account_type, statement_section, sub_section, normal_balance, time_balance, fx_method, is_posting, is_suspended, allow_ic, cf_category, cf_line_item, is_cash, main_account_category, status, is_retained_earnings)
VALUES
  ('ZZ1000', 'ZZ cash', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 1, 'CASH', 'Published', 0),
  ('ZZ4000', 'ZZ revenue', 'ZZCOA', '', 0, 'Revenue', 'Profit and Loss', 'Revenue', 'Credit', 'Period', 'average', 1, 0, 0, '', '', 0, 'REVENUE', 'Published', 0);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2018, 6, 'FY2018-P06', 'Jun 2018', 'Regular', '2018-06-01', '2018-06-30', 'Q2', 'Closed'),
  (2024, 6, 'FY2024-P06', 'Jun 2024', 'Regular', '2024-06-01', '2024-06-30', 'Q2', 'Closed'),
  (2025, 6, 'FY2025-P06', 'Jun 2025', 'Regular', '2025-06-01', '2025-06-30', 'Q2', 'Open');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id, dim_business_unit, dim_cost_center, dim_department)
VALUES
  ('ZZH1', 'ZZE1', 2018, 6, 'ZZ1000', 100, 0, 'ZZ cash', 'ZZ-TBS-ZZH1', '2026-09-15 00:00:00', '', 'ZZ_EX', '', ''),
  ('ZZH1', 'ZZE1', 2018, 6, 'ZZ4000', 0, 100, 'ZZ revenue', 'ZZ-TBS-ZZH1', '2026-09-15 00:00:00', '', 'ZZ_EX', '', ''),
  ('ZZH1', 'ZZE1', 2018, 6, 'ZZ1000', 20, 0, 'ZZ cash', 'ZZ-TBS-ZZH1', '2026-09-15 00:00:00', '', 'ZZ_GX', '', ''),
  ('ZZH1', 'ZZE1', 2018, 6, 'ZZ4000', 0, 20, 'ZZ revenue', 'ZZ-TBS-ZZH1', '2026-09-15 00:00:00', '', 'ZZ_GX', '', ''),
  ('ZZH2', 'ZZE1', 2024, 6, 'ZZ1000', 3, 0, 'ZZ cash', 'ZZ-TBS-ZZH2', '2026-09-15 00:00:00', '', 'ZZ_AX', '', ''),
  ('ZZH2', 'ZZE1', 2024, 6, 'ZZ4000', 0, 3, 'ZZ revenue', 'ZZ-TBS-ZZH2', '2026-09-15 00:00:00', '', 'ZZ_AX', '', ''),
  ('ZZH3', 'ZZE1', 2025, 6, 'ZZ1000', 500, 0, 'ZZ cash', 'ZZ-TBS-ZZH3', '2026-09-15 00:00:00', '', 'ZZ_EX', '', ''),
  ('ZZH3', 'ZZE1', 2025, 6, 'ZZ4000', 0, 500, 'ZZ revenue', 'ZZ-TBS-ZZH3', '2026-09-15 00:00:00', '', 'ZZ_EX', '', ''),
  ('ZZH3', 'ZZE1', 2025, 6, 'ZZ1000', 4000, 0, 'ZZ cash', 'ZZ-TBS-ZZH3', '2026-09-15 00:00:00', '', 'ZZ_AX', '', ''),
  ('ZZH3', 'ZZE1', 2025, 6, 'ZZ4000', 0, 4000, 'ZZ revenue', 'ZZ-TBS-ZZH3', '2026-09-15 00:00:00', '', 'ZZ_AX', '', '');
--
-- Budgets (row H4). A budget carries no business unit (dim_business_unit is in_budget: false), so the move of
-- ZZ_EX is mirrored on dim_cost_center as hierarchy ZZ_DIV_CC, same codes and windows:
--   ZZ_ROOT group 2010-01-01 .. open | ZZ_B group 2010-01-01 .. open | ZZ_E group 2017-01-01 .. 2024-12-31
--   ZZ_EX leaf under ZZ_E 2017-01-01 .. 2024-12-31, under ZZ_B 2025-01-01 .. open
-- Budget Entry lines (epm_raw.budget_entries, debit/credit, Period movement), scenario ZZ_PLAN_H, base layer, ZZ4000, cost centre ZZ_EX:
--   FY2018 P6 -70 -> ZZ_EX, ZZ_E, ZZ_ROOT (not ZZ_B) | FY2025 P6 -600 -> ZZ_EX, ZZ_B, ZZ_ROOT (not ZZ_E).
-- gold_spread_budget also reads epm_gold.budget_annual_input and epm_gold.spread_profiles, empty here.
INSERT INTO epm_staging.reporting_hierarchies
  (hierarchy_name, dimension, member_code, member_label, parent_member_code, is_group, hierarchy_level, path, effective_from, effective_to, is_default, status, member_effective_from, member_effective_to)
VALUES
  ('ZZ_DIV_CC', 'dim_cost_center', 'ZZ_ROOT', 'ZZ root', '', 1, 1, 'ZZ_ROOT', '', '', 1, 'Published', '2010-01-01', '2299-12-31'),
  ('ZZ_DIV_CC', 'dim_cost_center', 'ZZ_B', 'ZZ B', 'ZZ_ROOT', 1, 2, 'ZZ_ROOT/ZZ_B', '', '', 1, 'Published', '2010-01-01', '2299-12-31'),
  ('ZZ_DIV_CC', 'dim_cost_center', 'ZZ_E', 'ZZ E', 'ZZ_ROOT', 1, 2, 'ZZ_ROOT/ZZ_E', '', '', 1, 'Published', '2017-01-01', '2024-12-31'),
  ('ZZ_DIV_CC', 'dim_cost_center', 'ZZ_EX', 'ZZ EX', 'ZZ_E', 0, 3, 'ZZ_ROOT/ZZ_E/ZZ_EX', '', '', 1, 'Published', '2017-01-01', '2024-12-31'),
  ('ZZ_DIV_CC', 'dim_cost_center', 'ZZ_EX', 'ZZ EX', 'ZZ_B', 0, 3, 'ZZ_ROOT/ZZ_B/ZZ_EX', '', '', 1, 'Published', '2025-01-01', '2299-12-31');
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis, dim_cost_center, dim_department)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_PLAN_H', 'base', 'ZZE1', 2018, 6, 'ZZ4000', 0, 70, 'USD', 'Period movement', 'ZZ_EX', ''),
  ('ZZ-BE-2', 'ZZ-CY-2026', 'ZZ_PLAN_H', 'base', 'ZZE1', 2025, 6, 'ZZ4000', 0, 600, 'USD', 'Period movement', 'ZZ_EX', '');
--
-- Scenarios (row H5b): gold_scenario_trial_balance and gold_variance_analysis read epm_gold.scenario_definitions;
-- ZZ_PLAN_H must be an active budget-type scenario for its budget rows to reach variance.
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ACTUAL', 'Actual', 'actual', 1),
  ('ZZ_PLAN_H', 'ZZ plan H', 'budget', 1);
--
-- Unassigned per period (row H6): business unit ZZ_ZX becomes a leaf of ZZ_DIV (under ZZ_B) only from
-- 2025-01-01, and carries actuals in FY2024 P6 (7) and FY2025 P6 (9). So ZZ_ZX is unassigned in FY2024 and
-- assigned in FY2025. The cash line has no business unit, so ZZ_ZX adds nothing to the ZZ1000 nodes that
-- assert_hierarchy_node_as_of checks.
INSERT INTO epm_staging.reporting_hierarchies
  (hierarchy_name, dimension, member_code, member_label, parent_member_code, is_group, hierarchy_level, path, effective_from, effective_to, is_default, status, member_effective_from, member_effective_to)
VALUES
  ('ZZ_DIV', 'dim_business_unit', 'ZZ_ZX', 'ZZ ZX', 'ZZ_B', 0, 3, 'ZZ_ROOT/ZZ_B/ZZ_ZX', '', '', 1, 'Published', '2025-01-01', '2299-12-31');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id, dim_business_unit, dim_cost_center, dim_department)
VALUES
  ('ZZH2', 'ZZE1', 2024, 6, 'ZZ1000', 7, 0, 'ZZ cash', 'ZZ-TBS-ZZH2', '2026-09-15 00:00:00', '', '', '', ''),
  ('ZZH2', 'ZZE1', 2024, 6, 'ZZ4000', 0, 7, 'ZZ revenue', 'ZZ-TBS-ZZH2', '2026-09-15 00:00:00', '', 'ZZ_ZX', '', ''),
  ('ZZH3', 'ZZE1', 2025, 6, 'ZZ1000', 9, 0, 'ZZ cash', 'ZZ-TBS-ZZH3', '2026-09-15 00:00:00', '', '', '', ''),
  ('ZZH3', 'ZZE1', 2025, 6, 'ZZ4000', 0, 9, 'ZZ revenue', 'ZZ-TBS-ZZH3', '2026-09-15 00:00:00', '', 'ZZ_ZX', '', '');
-- The three batches' control rows (row counts include row H6's lines).
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZH1', 'ZZ-TBS-ZZH1', 'ZZE1', 2018, 6, 4, '2026-09-15 00:00:00', 'Period movement'),
  ('ZZH2', 'ZZ-TBS-ZZH2', 'ZZE1', 2024, 6, 4, '2026-09-15 00:00:00', 'Period movement'),
  ('ZZH3', 'ZZ-TBS-ZZH3', 'ZZE1', 2025, 6, 6, '2026-09-15 00:00:00', 'Period movement');
