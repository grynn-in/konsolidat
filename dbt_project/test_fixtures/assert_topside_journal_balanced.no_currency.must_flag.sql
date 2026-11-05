-- gate: build gold_consolidation_adjustments assert_topside_journal_balanced
-- gate: expect assert_topside_journal_balanced flag 1
-- konsol#353 follow-up: a journal whose group declares no reporting currency
-- with a minor unit has no tolerance to judge it by. It is reported, never
-- judged at a default (no silent fallback): here a balanced journal in group
-- ZZG, which has no root row in consolidation_groups.
-- Red (flat 0.01): balanced, PASS. Green: reported, 1 result.
-- tables: epm_staging.consolidation_adjustments epm_gold.consolidation_groups epm_gold.currencies
INSERT INTO epm_staging.consolidation_adjustments
  (consolidation_group, adjustment_type, journal_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, posted_by, status, approved_by, reverse_fiscal_year, reverse_fiscal_period)
VALUES
  ('ZZG', 'topside', 'ZZJ-NOCUR-1', 'ZZE1', 2026, 3, 'ZZ1100', 100, 0, 'd', 'zz', 'Approved', 'zz', 0, 0),
  ('ZZG', 'topside', 'ZZJ-NOCUR-1', 'ZZE1', 2026, 3, 'ZZ2100', 0, 100, 'c', 'zz', 'Approved', 'zz', 0, 0);
