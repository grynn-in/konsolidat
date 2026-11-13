-- gate: build gold_spread_budget assert_budget_fact_grain_unique assert_spread_sums_to_annual
-- gate: expect assert_budget_fact_grain_unique pass
-- gate: expect assert_spread_sums_to_annual pass
-- konsol#348 S2 (R2): the manual branch of gold_spread_budget reads epm_raw.budget_entries. Each line
-- is debit/credit; the fact carries net = debit - credit (debit positive, signed like actuals, BUD-7),
-- summed to one row per (scenario, entity, year, period, account, budget dims, layer).
--   * ZZ4000 base P2 has two lines (400 + 200 credit): one fact row of -600, so the grain test passes
--     only if the lines are summed, not carried one row each.
--   * ZZ4000 challenge P1 is its own layer: a second legitimate row at that grain.
--   * ZZ6000 base P1 carries a cost centre: dimensions are part of the grain.
--   * ZZ4000 base P3 is a 'Year-to-date movement' line: R2 sums 'Period movement' rows only (Q15-c);
--     assert_budget_basis_supported (R9) names it. It must not reach the fact.
--
-- gold_spread_budget also reads these tables, empty here, so they are named to exist (empty):
-- epm_gold.budget_annual_input, epm_gold.spread_profiles, epm_gold.budget_monthly_input.
--
-- epm_raw.budget_entries is konsol's (I3) and may not exist on the stack yet: create it with the body
-- of clickhouse/init-db.sql (pinned by tests/test_budget_raw_ddl.py), then add the site's budget
-- dimensions as konsol does, by ALTER.
CREATE TABLE IF NOT EXISTS epm_raw.budget_entries (
    entry_name String, cycle String, scenario_id String, layer String,
    data_area_id String, fiscal_year UInt16, fiscal_period UInt8,
    main_account String, debit Decimal(18,4), credit Decimal(18,4),
    currency String, amount_basis String
) ENGINE = MergeTree
ORDER BY (scenario_id, data_area_id, fiscal_year, fiscal_period, layer, main_account);
ALTER TABLE epm_raw.budget_entries ADD COLUMN IF NOT EXISTS dim_cost_center String DEFAULT '';
ALTER TABLE epm_raw.budget_entries ADD COLUMN IF NOT EXISTS dim_department String DEFAULT '';
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis, dim_cost_center, dim_department)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 600, 'USD', 'Period movement', '', ''),
  ('ZZ-BE-2', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 2, 'ZZ4000', 0, 400, 'USD', 'Period movement', '', ''),
  ('ZZ-BE-2', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 2, 'ZZ4000', 0, 200, 'USD', 'Period movement', '', ''),
  ('ZZ-BE-3', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'challenge', 'ZZE1', 2026, 1, 'ZZ4000', 100, 0, 'USD', 'Period movement', '', ''),
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ6000', 300, 0, 'USD', 'Period movement', 'ZZCC1', ''),
  ('ZZ-BE-4', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 3, 'ZZ4000', 0, 1800, 'USD', 'Year-to-date movement', '', '');
