-- assert_all_layers_present: must PASS. One row in each of the four layers the test expects.
INSERT INTO epm_gold.gold_fully_consolidated_tb
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name,
   dim_business_unit, dim_cost_center, dim_department, reporting_currency, amount, adjustment_type, journal_id)
VALUES
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ1000', 'cash', '', '', '', 'USD', 100, 'entity', ''),
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ1000', 'cash', '', '', '', 'USD', -10, 'ic_elimination', 'ZZJ1'),
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ3900', 'cta', '', '', '', 'USD', 5, 'cta', ''),
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ3000', 'share capital', '', '', '', 'USD', -95, 'topside', 'ZZJ2');
