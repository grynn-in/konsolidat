-- gate: build +assert_budget_currency_is_entity_currency
-- gate: expect assert_budget_currency_is_entity_currency pass
-- konsol#348 S3 B7 (QB3 a): a budget in its entity's accounting currency is not named. Entity ZZE1 keeps its
-- books in USD (epm_staging.entities, konsol's Entity master; silver_entity_currencies is built from it).
-- Its budget lines (ZZ4000, ZZ6000, Period movement) and its annual input (ZZ7000, flat profile) are all USD.
-- `+assert_budget_currency_is_entity_currency` builds gold_spread_budget and silver_entity_currencies from
-- these rows and must PASS.
--
-- Red on the S2 model: gold_spread_budget has no `currency` column, so the test errors (missing column);
-- green once the fact carries it (B4). The live annual table may predate `cycle` (B3w): add it to the
-- scratch clone first.
ALTER TABLE epm_gold.budget_annual_input ADD COLUMN IF NOT EXISTS cycle String;
INSERT INTO epm_staging.entities
  (data_area_id, entity_name, parent_entity, is_group, status, accounting_currency, country, erp_source)
VALUES
  ('ZZE1', 'ZZ entity 1', '', 0, 'Published', 'USD', 'US', '');
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis, dim_cost_center, dim_department)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 600, 'USD', 'Period movement', '', ''),
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ6000', 300, 0, 'USD', 'Period movement', 'ZZCC1', '');
INSERT INTO epm_gold.budget_annual_input
  (scenario_id, data_area_id, fiscal_year, cycle, main_account, layer, currency, annual_amount, spread_profile_id, submitted_by)
VALUES
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ-CY-2026', 'ZZ7000', 'base', 'USD', 1200, 'ZZ_FLAT', 'zz');
INSERT INTO epm_gold.spread_profiles (profile_id, profile_name, fiscal_period, weight) VALUES
  ('ZZ_FLAT', 'ZZ flat', 1, 1), ('ZZ_FLAT', 'ZZ flat', 2, 1), ('ZZ_FLAT', 'ZZ flat', 3, 1), ('ZZ_FLAT', 'ZZ flat', 4, 1),
  ('ZZ_FLAT', 'ZZ flat', 5, 1), ('ZZ_FLAT', 'ZZ flat', 6, 1), ('ZZ_FLAT', 'ZZ flat', 7, 1), ('ZZ_FLAT', 'ZZ flat', 8, 1),
  ('ZZ_FLAT', 'ZZ flat', 9, 1), ('ZZ_FLAT', 'ZZ flat', 10, 1), ('ZZ_FLAT', 'ZZ flat', 11, 1), ('ZZ_FLAT', 'ZZ flat', 12, 1);
