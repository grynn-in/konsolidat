-- gate: expect assert_cash_flow_excludes_nci_attribution flag 1
-- assert_cash_flow_excludes_nci_attribution: must FAIL with exactly 1 result: ZZG 2026 P1 Financing /
-- ZZ non-controlling interest, main_accounts ['ZZ3400'], cash_flow_amount 18.00.
-- gold_consolidated_cash_flow leaves the nci_attribution layer out, so a build can never produce the row
-- this test flags: the three tables are seeded here as a model that forgot the exclusion would build them
-- (test mode, no `gate: build`). Two seed lines, one journal NCI-ZZG-ZZE1-2026-P1 that sums to zero:
--   Financing / ZZ non-controlling interest: ZZ3400 alone, attribution only (-18.00) -> cash-flow row
--     18.00 exists only because of the layer: FLAG.
--   Financing / ZZ equity: ZZ3100 attribution (+16.20) and ZZ3500 attribution (+1.80) share the line
--     with ZZ3000, whose entity row (-1,000) is a real equity movement -> the row (1,000 - 18.00 = 982.00)
--     is not the attribution's: NOT flagged (konsolidat#351; the per-account test flagged it too).
-- ZZ1000 cash (is_cash = 1, +1,000) is not a line; the two lines sum to 1,000, the cash movement, so the
-- seeded statement ties the way the model's would.
INSERT INTO epm_staging.cash_flow_categories
  (main_account, cf_category, cf_line_item, is_cash, status)
VALUES
  ('ZZ3000', 'Financing', 'ZZ equity', 0, 'Published'),
  ('ZZ3100', 'Financing', 'ZZ equity', 0, 'Published'),
  ('ZZ3500', 'Financing', 'ZZ equity', 0, 'Published'),
  ('ZZ3400', 'Financing', 'ZZ non-controlling interest', 0, 'Published'),
  ('ZZ1000', 'Operating', 'ZZ cash', 1, 'Published');
INSERT INTO epm_gold.gold_fully_consolidated_tb
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name,
   reporting_currency, amount, adjustment_type, journal_id)
VALUES
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ1000', 'ZZ cash',                     'USD',  1000.00, 'entity', ''),
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ3000', 'ZZ share capital',            'USD', -1000.00, 'entity', ''),
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ3100', 'ZZ retained earnings',        'USD',    16.20, 'nci_attribution', 'NCI-ZZG-ZZE1-2026-P1'),
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ3500', 'ZZ CTA',                      'USD',     1.80, 'nci_attribution', 'NCI-ZZG-ZZE1-2026-P1'),
  ('ZZG', 'ZZE1', 2026, 1, 'ZZ3400', 'ZZ non-controlling interest', 'USD',   -18.00, 'nci_attribution', 'NCI-ZZG-ZZE1-2026-P1');
INSERT INTO epm_gold.gold_consolidated_cash_flow
  (consolidation_group, fiscal_year, fiscal_period, cf_category, cf_line_item, cash_flow_amount)
VALUES
  ('ZZG', 2026, 1, 'Financing', 'ZZ equity',                   982.00),
  ('ZZG', 2026, 1, 'Financing', 'ZZ non-controlling interest',  18.00);
