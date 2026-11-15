-- gate: build +assert_budget_currency_is_entity_currency
-- gate: expect assert_budget_currency_is_entity_currency flag 1
-- konsol#348 S3 B7 (QB3 a): a budget line in another currency than its entity's is named. Entity ZZE1 keeps
-- its books in USD. Its ZZ4000 base line is in EUR; its ZZ6000 base line is in USD. Exactly 1 result:
-- (ZZ_PLAN_2026, ZZ-CY-2026, ZZE1, base, EUR) against entity currency USD. A test that cannot see the
-- fact's currency cannot name it.
--
-- gold_spread_budget also reads epm_gold.budget_annual_input and epm_gold.spread_profiles, empty here. The
-- live annual table may predate `cycle` (B3w): add it to the scratch clone first.
ALTER TABLE epm_gold.budget_annual_input ADD COLUMN IF NOT EXISTS cycle String;
INSERT INTO epm_staging.entities
  (data_area_id, entity_name, parent_entity, is_group, status, accounting_currency, country, erp_source)
VALUES
  ('ZZE1', 'ZZ entity 1', '', 0, 'Published', 'USD', 'US', '');
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis, dim_cost_center, dim_department)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 600, 'EUR', 'Period movement', '', ''),
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ6000', 300, 0, 'USD', 'Period movement', 'ZZCC1', '');
