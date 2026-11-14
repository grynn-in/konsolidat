-- gate: build gold_entity_ownership gold_equity_method_associates assert_equity_associate_has_average_rate
-- gate: refuse gold_equity_method_associates has no reporting currency to translate into
-- gate: expect assert_equity_associate_has_average_rate flag 2
-- Equity-method associate whose group has NO root row, must flag (konsolidat#279 / PRD-14).
--
-- The same rows as assert_equity_method_journal_balances.sql (associate ZZA in SEK at 30% under ZZG,
-- a 1,000 SEK profit in FY2026 P12 and 500 SEK in P13, SEK->EUR Average 0.09 approved at P12), with
-- ONE difference: epm_gold.consolidation_groups has no root row for ZZG (data_area_id = ''), so the
-- group has no reporting currency. Under join_use_nulls=0 the model reads reporting_currency = ''.
-- Before this guard the rate throwIf fired and told the operator to approve a SEK->'' rate.
--   gold_equity_method_associates must be REFUSED by its no_reporting_currency guard, naming
--     "ZZG/ZZA FY2026 P12" and "ZZG/ZZA FY2026 P13" ("has no reporting currency to translate into"),
--   assert_equity_associate_has_average_rate must FLAG exactly 2 rows, both with reason
--     no_reporting_currency (never 'missing': the approved SEK->EUR rate is not the problem):
--     ZZG / ZZA  SEK -> ''  FY2026 P12
--     ZZG / ZZA  SEK -> ''  FY2026 P13
-- Both are judged in ONE build because the test is severity warn: at error severity dbt skipped the
-- model after the flag (CI 42393401046: 'must be REFUSED, got SKIPPED') and the throwIf never ran.
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
  ('ZZA', 2026, 13, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 500, -500, 1);
-- konsolidat#279 defect 3: the model reads gold_trial_balance_by_partner for the year-end close marker; no close rows here.
ALTER TABLE epm_gold.gold_trial_balance_by_partner ADD COLUMN IF NOT EXISTS is_year_end_close UInt8 DEFAULT 0;
