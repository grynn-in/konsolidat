-- gate: expect assert_partial_period_pnl_matches_treatment pass
-- konsolidat#171 step 2c review F4: pins the DISPOSAL half of the amount oracle (the acquisition half is month_arithmetic*).
-- Decided by Deepak Pai: 18 Sep 2026 (treatment declared by the group root), 10 Nov 2026 Q2 C (disposal period inside the window, IFRS 10.B88).
-- April fiscal year (P6 = Sep 2026, 30 days). ZZG (USD), root 'Pro-rate by days', sells all of ZZD on 2026-09-20 (BD-ZZG-ZZD-2026-09-20):
-- the group held 20 of 30 days, 10/30 is removed. gold_consolidated_trial_balance ZZD P6 (group currency): ZZ4000 Cr 3,000, ZZ5000 Dr 1,500.
-- Expected line 105 (post_disposal_pnl): ZZ4000 +1,000, ZZ5000 -500 (= -group_amount x 10/30).
-- Model tables seeded: gold_business_disposal_journal carries the line 105 rows under test.
-- The live tables may predate the group's treatment column and the deal tables: bring them to shape.
-- Model rows as the 10/30 treatment posts them: ZZ4000 +1,000, ZZ5000 -500.
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS partial_period_treatment String DEFAULT '';
CREATE TABLE IF NOT EXISTS epm_staging.business_combinations (name String, consolidation_group String, acquired_entity String, acquisition_date Date, share_acquired_pct Float64, consideration_currency String, total_consideration Float64, net_assets_acquired Float64, fair_value_adjustments Float64, goodwill Float64, bargain_purchase_gain Float64, nci_at_acquisition Float64, ownership_period String) ENGINE = MergeTree ORDER BY name;
CREATE TABLE IF NOT EXISTS epm_staging.business_disposals (name String, consolidation_group String, disposed_entity String, disposal_date Date, share_disposed_pct Float64, retained_interest_pct Float64, proceeds_currency String, total_proceeds Float64, ownership_period String) ENGINE = MergeTree ORDER BY name;
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, is_equity, fx_method, is_posting, is_retained_earnings, uses_historical_rate)
VALUES
  ('ZZ4000', 'ZZ revenue', 'Revenue', 'Revenue', 1, 0, 0, 'average', 1, 0, 0),
  ('ZZ5000', 'ZZ cost', 'Expense', 'Expense', 1, 0, 0, 'average', 1, 0, 0),
  ('ZZ3100', 'ZZ retained earnings', 'Equity', 'Equity', 0, 1, 1, 'historical', 1, 1, 0);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Apr 2026', 'Regular', '2026-04-01', '2026-04-30', 'Q1', 'Open'),
  (2026, 2, 'FY2026-P02', 'May 2026', 'Regular', '2026-05-01', '2026-05-31', 'Q1', 'Open'),
  (2026, 3, 'FY2026-P03', 'Jun 2026', 'Regular', '2026-06-01', '2026-06-30', 'Q1', 'Open'),
  (2026, 4, 'FY2026-P04', 'Jul 2026', 'Regular', '2026-07-01', '2026-07-31', 'Q2', 'Open'),
  (2026, 5, 'FY2026-P05', 'Aug 2026', 'Regular', '2026-08-01', '2026-08-31', 'Q2', 'Open'),
  (2026, 6, 'FY2026-P06', 'Sep 2026', 'Regular', '2026-09-01', '2026-09-30', 'Q2', 'Open'),
  (2026, 7, 'FY2026-P07', 'Oct 2026', 'Regular', '2026-10-01', '2026-10-31', 'Q3', 'Open'),
  (2026, 8, 'FY2026-P08', 'Nov 2026', 'Regular', '2026-11-01', '2026-11-30', 'Q3', 'Open'),
  (2026, 9, 'FY2026-P09', 'Dec 2026', 'Regular', '2026-12-01', '2026-12-31', 'Q3', 'Open'),
  (2026, 10, 'FY2026-P10', 'Jan 2027', 'Regular', '2027-01-01', '2027-01-31', 'Q4', 'Open'),
  (2026, 11, 'FY2026-P11', 'Feb 2027', 'Regular', '2027-02-01', '2027-02-28', 'Q4', 'Open'),
  (2026, 12, 'FY2026-P12', 'Mar 2027', 'Regular', '2027-03-01', '2027-03-31', 'Q4', 'Open'),
  (2026, 13, 'FY2026-P13', 'FY2026 closing', 'Closing', '2027-03-31', '2027-03-31', 'Q4', 'Open');
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency, partial_period_treatment)
VALUES
  ('ZZG', '', 'ZZ Group', 'USD', 'Pro-rate by days'),
  ('ZZG', 'ZZD', 'ZZ Disposed 20 September', 'USD', '');
INSERT INTO epm_staging.business_disposals
  (name, consolidation_group, disposed_entity, disposal_date, share_disposed_pct, retained_interest_pct, proceeds_currency, total_proceeds, ownership_period)
VALUES
  ('BD-ZZG-ZZD-2026-09-20', 'ZZG', 'ZZD', '2026-09-20', 100, 0, 'USD', 2000, 'ZZ-OP-ZZD-1');
INSERT INTO epm_gold.gold_consolidated_trial_balance
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, is_equity, local_amount, accounting_currency, reporting_currency, ownership_pct, consolidation_method, group_amount)
VALUES
  ('ZZG', 'ZZD', 2026, 6, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, -3000, 'USD', 'USD', 100, 'full', -3000),
  ('ZZG', 'ZZD', 2026, 6, 'ZZ5000', 'ZZ cost', 'Expense', 0, 1, 0, 1500, 'USD', 'USD', 100, 'full', 1500);
INSERT INTO epm_gold.gold_business_disposal_journal
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name, adjustment_type, adjustment_amount, disposal_date, journal_id, line_no, account_role, deal)
VALUES
  ('ZZG', 'ZZD', 2026, 6, 'ZZ4000', 'ZZ revenue', 'disposal', 1000, '2026-09-20', 'DSP-ZZG-ZZD-2026-09-20', 105, 'post_disposal_pnl', 'BD-ZZG-ZZD-2026-09-20'),
  ('ZZG', 'ZZD', 2026, 6, 'ZZ5000', 'ZZ cost', 'disposal', -500, '2026-09-20', 'DSP-ZZG-ZZD-2026-09-20', 105, 'post_disposal_pnl', 'BD-ZZG-ZZD-2026-09-20');
