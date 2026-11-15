-- gate: build +gold_budget_at_hierarchy_node assert_budget_node_per_cycle_and_currency
-- gate: expect assert_budget_node_per_cycle_and_currency pass
-- konsol#348 S3 B11 (QB2 a, QB3 a): two approved forecast rounds stay apart in the budget rollup to a
-- reporting hierarchy node, and the node carries its currency. Scenario ZZ_FC_2026 is declared 'forecast'.
-- Round 1 (cycle ZZ-FC-R1) and round 2 (cycle ZZ-FC-R2) both budget FY2026 P1, entity ZZE1, base layer,
-- ZZ4000 on cost centre ZZCC1 (Period movement, USD): R1 -100 | R2 -110.
-- Reporting hierarchy ZZH_CC over dim_cost_center: group ZZCCG with leaf ZZCC1.
-- gold_budget_at_hierarchy_node must hold, at the ZZCC1 leaf and at ZZCCG, one row per cycle: R1 -100 USD
-- and R2 -110 USD; never one row of -210. `+gold_budget_at_hierarchy_node
-- assert_budget_node_per_cycle_and_currency` must BUILD and PASS.
--
-- Red on the S3-B10 model: the node model has no cycle or currency column and sums the rounds, so the test
-- compares each round's fact rows (-100, -110) with the one node row (-210) and FAILS 2.
--
-- gold_spread_budget reads these too, empty here, so they are named to exist (empty): epm_gold.budget_annual_input,
-- epm_gold.spread_profiles. The live annual table may predate `cycle` (B3w): add it to the scratch clone first.
-- konsol#287: the budget input tables name no dimension; konsol adds the site's declared ones. These rows carry
-- dim_cost_center and dim_department, so the columns are added first, for a stack whose site declares neither.
ALTER TABLE epm_gold.budget_annual_input ADD COLUMN IF NOT EXISTS cycle String;
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open'),
  (2026, 13, 'FY2026-P13', 'FY2026 closing', 'Closing', '2026-12-31', '2026-12-31', 'Q4', 'Open');
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ZZ_FC_2026', 'ZZ forecast 2026', 'forecast', 1);
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis, dim_cost_center, dim_department)
VALUES
  ('ZZ-BE-R1', 'ZZ-FC-R1', 'ZZ_FC_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 100, 'USD', 'Period movement', 'ZZCC1', ''),
  ('ZZ-BE-R2', 'ZZ-FC-R2', 'ZZ_FC_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 110, 'USD', 'Period movement', 'ZZCC1', '');
INSERT INTO epm_staging.reporting_hierarchies
  (hierarchy_name, dimension, member_code, member_label, parent_member_code, is_group, hierarchy_level, path, effective_from, effective_to, is_default, status)
VALUES
  ('ZZH_CC', 'dim_cost_center', 'ZZCCG', 'ZZ cost centre group', '', 1, 1, 'ZZCCG', '', '', 1, 'Published'),
  ('ZZH_CC', 'dim_cost_center', 'ZZCC1', 'ZZ cost centre 1', 'ZZCCG', 0, 2, 'ZZCCG/ZZCC1', '', '', 1, 'Published');
