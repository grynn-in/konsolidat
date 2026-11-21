-- gate: expect assert_waterfall_covers_every_adjustment_type pass
-- konsolidat#316 7h: every adjustment_type the fully consolidated TB carries must sit in a waterfall bucket.
-- 'journal_close' (konsolidat#316 7g) must sit in a waterfall bucket: red until the bucket exists (7h).
INSERT INTO epm_gold.gold_fully_consolidated_tb
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name,
   reporting_currency, amount, adjustment_type, journal_id)
VALUES
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ1000', 'x', 'USD', 1, 'entity', ''),
  ('ZZG', 'ZZE1', 2026, 13, 'ZZ3100', 'x', 'USD', 1, 'journal_close', '');
