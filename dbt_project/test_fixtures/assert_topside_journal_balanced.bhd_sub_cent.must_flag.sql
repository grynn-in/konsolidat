-- gate: build gold_consolidation_adjustments assert_topside_journal_balanced
-- gate: expect assert_topside_journal_balanced flag 1
-- konsol#353 follow-up: the tolerance is one unit of the journal currency's
-- minor unit, not a flat 0.01 (currency-scaled, Deepak Pai, 18 Sep 2026,
-- konsolidat#209). A BHD journal (minor unit 3, one unit 0.001) out by 0.004
-- (debit 0.024 against credit 0.020) must be flagged.
-- Red (flat 0.01): 0.004 is inside the tolerance: PASS, a test that cannot
-- fail for a 3-decimal currency. Green: 0.004 > 0.001: 1 result.
-- tables: epm_staging.consolidation_adjustments epm_gold.consolidation_groups epm_gold.currencies
INSERT INTO epm_gold.consolidation_groups (consolidation_group, data_area_id, entity_name, reporting_currency) VALUES ('ZZG', '', 'ZZ Group', 'BHD');
INSERT INTO epm_gold.currencies (currency_code, currency_name, symbol, minor_unit) VALUES ('BHD', 'ZZ BHD', 'BHD', 3);
INSERT INTO epm_staging.consolidation_adjustments
  (consolidation_group, adjustment_type, journal_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, posted_by, status, approved_by, reverse_fiscal_year, reverse_fiscal_period)
VALUES
  ('ZZG', 'topside', 'ZZJ-BHD-3', 'ZZE1', 2026, 3, 'ZZ1100', 0.024, 0, 'd', 'zz', 'Approved', 'zz', 0, 0),
  ('ZZG', 'topside', 'ZZJ-BHD-3', 'ZZE1', 2026, 3, 'ZZ2100', 0, 0.020, 'c', 'zz', 'Approved', 'zz', 0, 0);
