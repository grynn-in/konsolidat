-- assert_all_layers_present: must FAIL with exactly 3 results (konsolidat#238, #249).
-- The fully consolidated TB holds only the entity layer: ic_elimination, cta and topside
-- are genuinely absent, so the test must name all three. adjustment_type is a String, so
-- a `LEFT JOIN ... WHERE actual.layer IS NULL` reads '' for the unmatched rows under
-- join_use_nulls = 0 and reports nothing; this fixture is what shows that.
INSERT INTO epm_gold.gold_fully_consolidated_tb
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name,
   dim_business_unit, dim_cost_center, dim_department, reporting_currency, amount, adjustment_type, journal_id)
VALUES
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ1000', 'cash', '', '', '', 'USD', 100, 'entity', ''),
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ3000', 'share capital', '', '', '', 'USD', -100, 'entity', '');
