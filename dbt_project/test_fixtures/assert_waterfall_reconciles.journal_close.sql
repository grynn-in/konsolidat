-- gate: build gold_consolidation_waterfall assert_waterfall_reconciles
-- gate: expect assert_waterfall_reconciles pass
-- gate: expect gold_consolidation_waterfall built
-- konsolidat#316 7h: a journal_close row (FY2026 P13, moves 100 of P&L into retained earnings) must land in a
-- waterfall bucket, so final_amount equals the sum of the buckets. A guard, not red before the bucket: the close
-- nets to 0 per group and period, so an unbucketed journal_close cannot move final_amount against the buckets;
-- assert_waterfall_covers_every_adjustment_type is what catches it.
INSERT INTO epm_gold.gold_fully_consolidated_tb
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name,
   reporting_currency, amount, adjustment_type, journal_id)
VALUES
  ('ZZG', 'ZZE1', 2026, 12, 'ZZ4000', 'x', 'USD', -100, 'entity', ''),
  ('ZZG', 'ZZE1', 2026, 13, 'ZZ4000', 'x', 'USD', 100, 'journal_close', 'JCLOSE_ZZG_2026'),
  ('ZZG', 'ZZE1', 2026, 13, 'ZZ3100', 'x', 'USD', -100, 'journal_close', 'JCLOSE_ZZG_2026');
