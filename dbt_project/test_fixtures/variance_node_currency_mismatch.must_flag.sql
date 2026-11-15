-- gate: build +gold_variance_at_hierarchy_node assert_variance_node_single_currency --exclude assert_budget_currency_is_entity_currency assert_variance_single_currency
-- gate: expect assert_variance_node_single_currency flag 2
-- konsol#348 S3 B11 (QB3 a): gold_variance_at_hierarchy_node carries the currency through the rollup and never
-- sums two currencies at a node. Copied from variance_node_two_budgets.sql with one budget scenario whose line is
-- in EUR against USD actuals:
-- Entity ZZE1 (USD), FY2026 P1. Trial balance upload (period movement), cost centre ZZCC1 on both rows
--   (konsol#255: a submission carries the site's declared dimensions): ZZ1000 cash Dr 1000 | ZZ4000 revenue Cr 1000.
-- Declared scenarios: ACTUAL (actual), ZZ_PLAN_2026 (budget, active).
-- Budget Entry line (epm_raw.budget_entries, Period movement), base layer, FY2026 P1 on ZZ4000, cost centre ZZCC1:
--   ZZ_PLAN_2026 -1200 in EUR.
-- Reporting hierarchy ZZH_CC over dim_cost_center: group ZZCCG with leaf ZZCC1.
-- gold_variance_analysis holds two rows for (ZZE1, 2026, 1, ZZ4000, ZZCC1, ZZ_PLAN_2026): USD actual -1000 and
-- EUR budget -1200 (B8). The node model must carry both to the ZZCC1 leaf and to ZZCCG as separate rows, so
-- assert_variance_node_single_currency must FLAG exactly those two node keys (2 rows); ZZ1000 is USD only.
--
-- Red on the S3-B10 model: the node model has no `currency` column, so the test errors (missing column).
--
-- assert_budget_currency_is_entity_currency (B7) and assert_variance_single_currency (B8), both error, name this
-- EUR line upstream, and in a build their failure would skip every model below; they are excluded here on
-- purpose: this fixture proves the backstop at the node can fail, which is only reachable past those guards.
--
-- The lineage of gold_scenario_trial_balance reads these tables too, empty here, so they are named to exist
-- (empty): epm_raw.budget_register_entries, epm_raw.fiscal_calendar_years,
-- epm_raw.general_journal_account_entry_bi_entities, epm_raw.general_journal_entry_bi_entities,
-- epm_gold.budget_annual_input, epm_gold.entity_fiscal_calendars, epm_gold.spread_profiles,
-- epm_staging.dimension_mappings.
--
-- The live submission tables and chart may predate their partner, basis and retained-earnings columns: add them first.
-- konsol#348 S3 B4: gold_spread_budget reads budget_annual_input.cycle (B3w); the live table may predate it:
-- add it to the scratch clone first.
ALTER TABLE epm_gold.budget_annual_input ADD COLUMN IF NOT EXISTS cycle String;
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS partner_data_area_id String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submissions ADD COLUMN IF NOT EXISTS dim_cost_center String DEFAULT '';
ALTER TABLE epm_raw.trial_balance_submission_control ADD COLUMN IF NOT EXISTS amount_basis String DEFAULT '';
ALTER TABLE epm_staging.main_accounts ADD COLUMN IF NOT EXISTS is_retained_earnings UInt8 DEFAULT 0;
-- konsol#287: the budget input tables name no dimension; konsol adds the site's
-- declared ones. These rows carry dim_cost_center and dim_department, so the
-- columns are added first, for a stack whose site declares neither.
-- konsol#348 S3 B6: gold_scenario_trial_balance now carries the entity's accounting currency from
-- silver_entity_currencies (epm_staging.entities), and the build runs assert_every_tb_entity_has_a_currency
-- and assert_budget_currency_is_entity_currency on the way, so the entity declares its currency, as on a site.
INSERT INTO epm_staging.entities
  (data_area_id, entity_name, parent_entity, is_group, status, accounting_currency, country, erp_source)
VALUES
  ('ZZE1', 'ZZ entity 1', '', 0, 'Published', 'USD', 'US', '');
INSERT INTO epm_staging.main_accounts
  (main_account, account_name, chart_of_accounts, parent_account, is_group, account_type, statement_section, sub_section, normal_balance, time_balance, fx_method, is_posting, is_suspended, allow_ic, cf_category, cf_line_item, is_cash, main_account_category, status, is_retained_earnings)
VALUES
  ('ZZ1000', 'ZZ cash', 'ZZCOA', '', 0, 'Asset', 'Balance Sheet', 'Current Assets', 'Debit', 'Balance', 'closing', 1, 0, 0, '', '', 1, 'CASH', 'Published', 0),
  ('ZZ4000', 'ZZ revenue', 'ZZCOA', '', 0, 'Revenue', 'Profit and Loss', 'Revenue', 'Credit', 'Period', 'average', 1, 0, 0, '', '', 0, 'REVENUE', 'Published', 0);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open'),
  (2026, 13, 'FY2026-P13', 'FY2026 closing', 'Closing', '2026-12-31', '2026-12-31', 'Q4', 'Open');
INSERT INTO epm_raw.trial_balance_submissions
  (batch_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, submission_name, submitted_at, partner_data_area_id, dim_cost_center)
VALUES
  ('ZZB1', 'ZZE1', 2026, 1, 'ZZ1000', 1000, 0, '', 'ZZ-TBS-1', '2026-02-05 09:00:00', '', 'ZZCC1'),
  ('ZZB1', 'ZZE1', 2026, 1, 'ZZ4000', 0, 1000, '', 'ZZ-TBS-1', '2026-02-05 09:00:00', '', 'ZZCC1');
INSERT INTO epm_raw.trial_balance_submission_control
  (batch_id, submission_name, data_area_id, fiscal_year, fiscal_period, row_count, claimed_at, amount_basis)
VALUES
  ('ZZB1', 'ZZ-TBS-1', 'ZZE1', 2026, 1, 2, '2026-02-05 09:00:00', 'Period movement');
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ACTUAL', 'Actual', 'actual', 1),
  ('ZZ_PLAN_2026', 'ZZ plan 2026', 'budget', 1);
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis, dim_cost_center, dim_department)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 1200, 'EUR', 'Period movement', 'ZZCC1', '');
INSERT INTO epm_staging.reporting_hierarchies
  (hierarchy_name, dimension, member_code, member_label, parent_member_code, is_group, hierarchy_level, path, effective_from, effective_to, is_default, status)
VALUES
  ('ZZH_CC', 'dim_cost_center', 'ZZCCG', 'ZZ cost centre group', '', 1, 1, 'ZZCCG', '', '', 1, 'Published'),
  ('ZZH_CC', 'dim_cost_center', 'ZZCC1', 'ZZ cost centre 1', 'ZZCCG', 0, 2, 'ZZCCG/ZZCC1', '', '', 1, 'Published');
