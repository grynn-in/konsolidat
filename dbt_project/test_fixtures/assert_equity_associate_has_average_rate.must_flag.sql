-- gate: build gold_entity_ownership gold_equity_method_associates assert_equity_associate_has_average_rate
-- gate: refuse gold_equity_method_associates no usable governed Average rate
-- gate: expect assert_equity_associate_has_average_rate flag 2
-- Equity-method associate with NO governed Average rate, must flag (konsolidat#279 / PRD-14).
--
-- The same group, associate, calendar, chart and trial balance as assert_equity_method_journal_balances.sql
-- (group ZZG in EUR, associate ZZA in SEK at 30%, a 1,000 SEK profit in FY2026 P12 and 500 SEK in the
-- Closing period P13), with ONE difference: the governed SEK->EUR FY2026 P12 row is the Closing rate
-- only. The model reads the Average rate, and the Closing period P13 reads P12's (rate_period_map()),
-- so neither period has a usable rate:
--   gold_equity_method_associates must be REFUSED (its throwIf, "no usable governed Average rate"),
--   assert_equity_associate_has_average_rate must FLAG exactly 2 rows:
--     ZZG / ZZA  SEK -> EUR  FY2026 P12  missing
--     ZZG / ZZA  SEK -> EUR  FY2026 P13  missing   (keyed on P12's rate, which is not there)
-- The test reads the model's inputs, never the model, which is why it still runs here.
-- The model's direct inputs are seeded as model tables (gold_trial_balance, silver_main_accounts,
-- silver_entity_currencies) and gold_entity_ownership is built from the seeded staging rows.
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, is_equity, fx_method, is_posting, is_retained_earnings, uses_historical_rate)
VALUES
  ('ZZ1000', 'ZZ cash', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
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
  ('EUR', 'SEK', 2026, 12, 'Closing', 0.10, 'ZZ-GER-2026-12');
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZA', 2026, 12, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 1000, 0, 1000, 1),
  ('ZZA', 2026, 12, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 1000, -1000, 1),
  ('ZZA', 2026, 13, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 500, 0, 500, 1),
  ('ZZA', 2026, 13, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 500, -500, 1);
