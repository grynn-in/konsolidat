-- gate: build gold_spread_budget gold_scenario_trial_balance assert_scenario_rows_declared
-- gate: expect assert_scenario_rows_declared flag 1
-- konsol#348 S2 (R2): rows in epm_raw.budget_entries reach the budget fact and the scenario trial
-- balance. Scenario ZZ_B1 has 'Period movement' lines and is declared nowhere, so
-- assert_scenario_rows_declared names ('ZZ_B1', 'budget', 'undeclared'): 1 result. On a model that does
-- not read epm_raw.budget_entries it names nothing.
-- ZZ_B2, also undeclared, has only a 'Year-to-date movement' line. R2 reads 'Period movement' rows only
-- (Q15-c), so ZZ_B2 has no rows and is not named: a second result means the basis is not filtered.
--
-- The lineage reads these tables too, empty here, so they are named to exist (empty):
-- epm_gold.budget_annual_input, epm_gold.spread_profiles, epm_gold.budget_monthly_input,
-- epm_gold.gold_trial_balance, epm_silver.silver_budget_entries, epm_gold.scenario_definitions.
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
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_B1', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 600, 'USD', 'Period movement'),
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_B1', 'base', 'ZZE1', 2026, 1, 'ZZ6000', 600, 0, 'USD', 'Period movement'),
  ('ZZ-BE-2', 'ZZ-CY-2026', 'ZZ_B2', 'base', 'ZZE1', 2026, 3, 'ZZ4000', 0, 1800, 'USD', 'Year-to-date movement');
