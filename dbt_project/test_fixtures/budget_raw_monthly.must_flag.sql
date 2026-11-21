-- gate: build gold_spread_budget gold_forecast_current_round gold_scenario_trial_balance assert_scenario_rows_declared
-- gate: expect assert_scenario_rows_declared flag 1
-- konsol#348 S2 (R2): rows in epm_raw.budget_entries reach the budget fact and the scenario trial
-- balance. Scenario ZZ_B1 has 'Period movement' lines and is declared nowhere, so
-- assert_scenario_rows_declared names ('ZZ_B1', 'budget', 'undeclared'): 1 result. On a model that does
-- not read epm_raw.budget_entries it names nothing.
-- ZZ_B2, also undeclared, has only a 'Period-end balance' line. The spread does not read that basis
-- (Q15-c, R10), so ZZ_B2 has no rows and is not named: a second result means the basis is not filtered.
--
-- The lineage reads these tables too, empty here, so they are named to exist (empty):
-- epm_gold.budget_annual_input, epm_gold.spread_profiles,
-- epm_gold.gold_trial_balance, epm_gold.scenario_definitions, and (konsol#348 S3 B6, the GL branch's
-- currency join; not built here, the selector names the gold models only) epm_silver.silver_entity_currencies.
-- konsol#348 S6 WA4: gold_scenario_trial_balance reads gold_forecast_current_round (the declared current
-- round of each forecast pair), so the selector builds it, empty here (no Current Forecast declared);
-- without it the model errors on the missing table and the test is SKIPPED.
--
-- epm_raw.budget_entries is konsol's (I3), declared in clickhouse/init-db.sql: fixture_gate.py creates it
-- (as zzg_raw) when the stack lacks it and adds the fixture budget dimension columns.
-- konsol#348 S3 B4: gold_spread_budget reads budget_annual_input.cycle (B3w); the live table may predate it:
-- add it to the scratch clone first.
ALTER TABLE epm_gold.budget_annual_input ADD COLUMN IF NOT EXISTS cycle String;
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_B1', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 600, 'USD', 'Period movement'),
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_B1', 'base', 'ZZE1', 2026, 1, 'ZZ6000', 600, 0, 'USD', 'Period movement'),
  ('ZZ-BE-2', 'ZZ-CY-2026', 'ZZ_B2', 'base', 'ZZE1', 2026, 3, 'ZZ4000', 0, 1800, 'USD', 'Period-end balance');
