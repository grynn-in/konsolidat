-- gate: build gold_consolidation_adjustments assert_topside_journal_balanced
-- gate: expect assert_topside_journal_balanced pass
-- konsol#353 follow-up: the tolerance is one unit of the journal currency's
-- minor unit (currency-scaled, Deepak Pai, 18 Sep 2026, konsolidat#209). A
-- JPY journal (minor unit 0, one unit 1) out by 1 yen is within it.
-- Red (flat 0.01): 1 > 0.01: FAIL 1. Green: 1 is not above 1: PASS.
-- tables: epm_staging.consolidation_adjustments epm_gold.consolidation_groups epm_gold.currencies
INSERT INTO epm_gold.consolidation_groups (consolidation_group, data_area_id, entity_name, reporting_currency) VALUES ('ZZG', '', 'ZZ Group', 'JPY');
INSERT INTO epm_gold.currencies (currency_code, currency_name, symbol, minor_unit) VALUES ('JPY', 'ZZ JPY', 'JPY', 0);
INSERT INTO epm_staging.consolidation_adjustments
  (consolidation_group, adjustment_type, journal_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, posted_by, status, approved_by, reverse_fiscal_year, reverse_fiscal_period)
VALUES
  ('ZZG', 'topside', 'ZZJ-JPY-1', 'ZZE1', 2026, 3, 'ZZ1100', 1001, 0, 'd', 'zz', 'Approved', 'zz', 0, 0),
  ('ZZG', 'topside', 'ZZJ-JPY-1', 'ZZE1', 2026, 3, 'ZZ2100', 0, 1000, 'c', 'zz', 'Approved', 'zz', 0, 0);
