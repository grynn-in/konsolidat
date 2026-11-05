-- gate: build gold_consolidation_adjustments assert_topside_journal_balanced
-- gate: expect assert_topside_journal_balanced pass
-- konsol#353 option C (Deepak Pai, 5 Nov 2026): a Consolidation Journal in a
-- 3-decimal currency (BHD, KWD, OMR) reaches gold exactly. konsol refuses a line
-- with more places than the currency's ISO minor unit and checks the balance
-- exactly in that unit, so this journal is balanced: five debits of 0.004
-- against one credit of 0.020, in BHD.
-- Red (epm_staging.consolidation_adjustments at Decimal(18,2)): each 0.004
-- is cut to 0.00 on insert, so the balanced journal arrives in gold as debit 0
-- against credit 0.02 and the test fails with 1 result. Green (Decimal(20,4)):
-- every line keeps its third place and the journal balances.
-- tables: epm_staging.consolidation_adjustments
INSERT INTO epm_staging.consolidation_adjustments
  (consolidation_group, adjustment_type, journal_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, posted_by, status, approved_by, reverse_fiscal_year, reverse_fiscal_period)
VALUES
  ('ZZG', 'topside', 'ZZJ-BHD-1', 'ZZE1', 2026, 3, 'ZZ1101', 0.004, 0, 'd1', 'zz', 'Approved', 'zz', 0, 0),
  ('ZZG', 'topside', 'ZZJ-BHD-1', 'ZZE1', 2026, 3, 'ZZ1102', 0.004, 0, 'd2', 'zz', 'Approved', 'zz', 0, 0),
  ('ZZG', 'topside', 'ZZJ-BHD-1', 'ZZE1', 2026, 3, 'ZZ1103', 0.004, 0, 'd3', 'zz', 'Approved', 'zz', 0, 0),
  ('ZZG', 'topside', 'ZZJ-BHD-1', 'ZZE1', 2026, 3, 'ZZ1104', 0.004, 0, 'd4', 'zz', 'Approved', 'zz', 0, 0),
  ('ZZG', 'topside', 'ZZJ-BHD-1', 'ZZE1', 2026, 3, 'ZZ1105', 0.004, 0, 'd5', 'zz', 'Approved', 'zz', 0, 0),
  ('ZZG', 'topside', 'ZZJ-BHD-1', 'ZZE1', 2026, 3, 'ZZ2100', 0, 0.020, 'c', 'zz', 'Approved', 'zz', 0, 0);
