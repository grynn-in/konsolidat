-- gate: build gold_consolidation_adjustments assert_topside_journal_balanced
-- gate: expect assert_topside_journal_balanced flag 1
-- konsol#353 option C (Deepak Pai, 5 Nov 2026): the converse of
-- assert_topside_journal_balanced.three_decimal.sql. A BHD journal out by
-- 0.012 (debit 0.016 against credit 0.004) must be flagged.
-- Red (Decimal(18,2)): the lines are cut to 0.01 and 0.00 on insert, an
-- imbalance of 0.01 that the test's 0.01 tolerance lets through: PASS, a test
-- that cannot fail. Green (Decimal(20,4)): 0.012 is above the tolerance: 1 result.
-- The group ZZG reports in BHD (minor unit 3): the test's tolerance is one
-- unit of that currency (konsol#353 follow-up).
-- tables: epm_staging.consolidation_adjustments epm_gold.consolidation_groups epm_gold.currencies
INSERT INTO epm_gold.consolidation_groups (consolidation_group, data_area_id, entity_name, reporting_currency) VALUES ('ZZG', '', 'ZZ Group', 'BHD');
INSERT INTO epm_gold.currencies (currency_code, currency_name, symbol, minor_unit) VALUES ('BHD', 'ZZ BHD', 'BHD', 3);
INSERT INTO epm_staging.consolidation_adjustments
  (consolidation_group, adjustment_type, journal_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, posted_by, status, approved_by, reverse_fiscal_year, reverse_fiscal_period)
VALUES
  ('ZZG', 'topside', 'ZZJ-BHD-2', 'ZZE1', 2026, 3, 'ZZ1100', 0.016, 0, 'd', 'zz', 'Approved', 'zz', 0, 0),
  ('ZZG', 'topside', 'ZZJ-BHD-2', 'ZZE1', 2026, 3, 'ZZ2100', 0, 0.004, 'c', 'zz', 'Approved', 'zz', 0, 0);
