-- gate: build gold_entity_ownership gold_equity_method_associates assert_equity_method_ignores_close_rows assert_equity_method_journal_balances assert_equity_income_formula
-- gate: expect assert_equity_method_ignores_close_rows pass
-- gate: expect assert_equity_method_journal_balances pass
-- gate: expect assert_equity_income_formula pass
-- konsolidat#279 defect 3: the equity method ignores the year-end close. This is the
-- assert_equity_method_journal_balances fixture (ZZG EUR, associate ZZA SEK 30%, 1,000 SEK profit in
-- P12, 500 SEK in P13, Average 0.09) PLUS the close silver_tb_movements synthesizes in FY2026's
-- Closing period P13 (konsolidat#259): ZZ4000 +1,500 / ZZ3100 -1,500, moving the year's 1,500 SEK profit
-- into retained earnings (marked is_year_end_close = 1 in gold_trial_balance_by_partner).
-- Read as P13's net income, P13 is -500 + 1,500 = +1,000 SEK, so the unfixed model posts EQ_INCOME
-- +27.00 in P13, opposite to the -13.50 share of P13's own 500 SEK. Expected: P12 -27.00, P13 -13.50.
-- Equity-method journal (PRD-14), the translated two-sided case: `gold_entity_ownership
-- gold_equity_method_associates assert_equity_method_journal_balances assert_equity_income_formula
-- assert_equity_associate_has_average_rate` must BUILD and all three tests must PASS on these rows
-- (the third, konsolidat#279: the SEK->EUR Average rate every associate period needs is approved).
--
-- Group ZZG reports in EUR. Associate ZZA keeps its books in SEK and is held at 30% under the
-- equity method (epm_staging.ownership_periods, method 'equity'), so gold_entity_ownership resolves
-- it as consolidation_method = 'equity' at 0.30 and gold_equity_method_associates posts one journal
-- per period it has a result in.
--
-- FY2026 P12 (Regular): cash ZZ1000 1,000 Dr | revenue ZZ4000 1,000 Cr: a profit of 1,000 SEK
--   (net_income = sum(period_net_amount) over P&L accounts = -1,000, debit minus credit).
--   Governed SEK->EUR FY2026 P12: Average 0.09 (Closing 0.10, not read by this model).
--   Expected journal EQ_ZZG_ZZA_2026_P12 (EUR): EQ_INCOME -27.00 (Cr share of profit)
--                                               EQ_INVEST +27.00 (Dr investment)   -> sums to 0.
-- FY2026 P13 (Closing): cash ZZ1000 500 Dr | revenue ZZ4000 500 Cr: a late 500 SEK profit posted
--   in the Closing period, which has NO governed rate of its own (as in konsol, rates are approved
--   per Regular period). rate_period_map() keys it on FY2026 P12's Average rate.
--   Expected journal EQ_ZZG_ZZA_2026_P13 (EUR): EQ_INCOME -13.50 / EQ_INVEST +13.50 -> sums to 0.
--
-- (The close and P13's own activity sit on separate rows, as if on different dimension values: a real
-- close is synthesized only in a Closing period the entity did not claim, so mixing them is a fixture shortcut.)
--
-- Before the fix the model never translated: both lines carried the SEK share labelled as EUR, -300
-- each (net -600) in P12 and -150 each (net -300) in P13, so assert_equity_method_journal_balances
-- flagged 2 journals and assert_equity_income_formula (now the translated oracle) flagged 2 rows.
--
-- The model's direct inputs are seeded as model tables (gold_trial_balance, silver_main_accounts,
-- silver_entity_currencies) and gold_entity_ownership is built from the seeded staging rows.
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, is_equity, fx_method, is_posting, is_retained_earnings, uses_historical_rate)
VALUES
  ('ZZ1000', 'ZZ cash', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ3100', 'ZZ retained earnings', 'Equity', 'Equity', 0, 1, 1, 'historical', 1, 1, 1),
  ('ZZ4000', 'ZZ revenue', 'Revenue', 'Revenue', 1, 0, 0, 'average', 1, 0, 0);
INSERT INTO epm_silver.silver_entity_currencies
  (data_area_id, accounting_currency)
VALUES
  ('ZZA', 'SEK');
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency)
VALUES
  ('ZZG', '', 'ZZ Group', 'EUR'),
  ('ZZG', 'ZZA', 'ZZ Associate', 'EUR');
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path)
VALUES
  ('ZZG', 'ZZA', 'ZZG', 'ZZA', 1, 1, 'ZZG/ZZA');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method)
VALUES
  ('ZZG', 'ZZA', '2020-01-01', '2149-06-06', 30, 'equity');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 12, 'FY2026-P12', 'Dec 2026', 'Regular', '2026-12-01', '2026-12-31', 'Q4', 'Open'),
  (2026, 13, 'FY2026-P13', 'FY2026 closing', 'Closing', '2026-12-31', '2026-12-31', 'Q4', 'Open');
INSERT INTO epm_staging.group_exchange_rates
  (to_currency, from_currency, fiscal_year, fiscal_period, rate_type, rate, document)
VALUES
  ('EUR', 'SEK', 2026, 12, 'Closing', 0.10, 'ZZ-GER-2026-12'),
  ('EUR', 'SEK', 2026, 12, 'Average', 0.09, 'ZZ-GER-2026-12');
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZA', 2026, 12, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 1000, 0, 1000, 1),
  ('ZZA', 2026, 12, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 1000, -1000, 1),
  ('ZZA', 2026, 13, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 500, 0, 500, 1),
  ('ZZA', 2026, 13, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 500, -500, 1),
  ('ZZA', 2026, 13, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 1500, 0, 1500, 1),
  ('ZZA', 2026, 13, 'ZZ3100', 'ZZ retained earnings', 'Equity', 1, 0, 0, 1500, -1500, 1);
-- gold_trial_balance_by_partner carries the close marker (the live table may predate it).
ALTER TABLE epm_gold.gold_trial_balance_by_partner ADD COLUMN IF NOT EXISTS is_year_end_close UInt8 DEFAULT 0;
INSERT INTO epm_gold.gold_trial_balance_by_partner
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, partner_data_area_id, period_debit, period_credit, period_net_amount, transaction_count, is_year_end_close)
VALUES
  ('ZZA', 2026, 12, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, '', 1000, 0, 1000, 1, 0),
  ('ZZA', 2026, 12, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', 0, 1000, -1000, 1, 0),
  ('ZZA', 2026, 13, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, '', 500, 0, 500, 1, 0),
  ('ZZA', 2026, 13, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', 0, 500, -500, 1, 0),
  ('ZZA', 2026, 13, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', 1500, 0, 1500, 1, 1),
  ('ZZA', 2026, 13, 'ZZ3100', 'ZZ retained earnings', 'Equity', 1, 0, '', 0, 1500, -1500, 1, 1);
