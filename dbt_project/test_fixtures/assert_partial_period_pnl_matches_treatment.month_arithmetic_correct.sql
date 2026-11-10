-- gate: expect assert_partial_period_pnl_matches_treatment pass
-- konsolidat#171 step 2c (T3): the amount oracle for mid-period P&L under the declared treatment.
-- Decided by Deepak Pai: 18 Sep 2026 (treatment declared by the group root), 10 Nov 2026 Q2 C.
--
-- April fiscal year: FY2026 P1 = Apr 2026 ... P9 = Dec 2026 ... P12 = Mar 2027, P13 Closing on 2027-03-31.
-- ZZG (USD), root 'Pro-rate by days', acquires ZZE on 2026-12-11 (BC-ZZG-ZZE-2026-12-11), so the deal
-- period is P9 (2026-12-01 to 2026-12-31, 31 days) and the share to remove is 10/31 (1 to 10 December).
-- Sign convention: adjustment = -group_amount * removed_fraction on every P&L account of the deal period.
-- gold_consolidated_trial_balance ZZE P9: ZZ4000 revenue -3,410 (credit), ZZ5000 cost +1,705 (debit).
-- Expected: ZZ4000 -(-3,410) * 10/31 = +1,100 ; ZZ5000 -(1,705) * 10/31 = -550.
-- Model rows as the 10/31 treatment posts them: ZZ4000 +1,100, ZZ5000 -550 and the balancing
-- retained-earnings line ZZ3100 -550 (not a P&L account, so not judged as an amount). Entity-period sums to 0.
-- The live tables may predate the group's treatment column and the deal tables: bring them to shape.
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
  ('ZZG', 'ZZE', 'ZZ Acquired 11 December', 'USD', '');
INSERT INTO epm_staging.business_combinations
  (name, consolidation_group, acquired_entity, acquisition_date, share_acquired_pct, consideration_currency, total_consideration, net_assets_acquired, fair_value_adjustments, goodwill, bargain_purchase_gain, nci_at_acquisition, ownership_period)
VALUES
  ('BC-ZZG-ZZE-2026-12-11', 'ZZG', 'ZZE', '2026-12-11', 100, 'USD', 1000, 1000, 0, 0, 0, 0, 'ZZ-OP-ZZE-1');
INSERT INTO epm_gold.gold_consolidated_trial_balance
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, is_equity, local_amount, accounting_currency, reporting_currency, ownership_pct, consolidation_method, group_amount)
VALUES
  ('ZZG', 'ZZE', 2026, 9, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, -3410, 'USD', 'USD', 100, 'full', -3410),
  ('ZZG', 'ZZE', 2026, 9, 'ZZ5000', 'ZZ cost', 'Expense', 0, 1, 0, 1705, 'USD', 'USD', 100, 'full', 1705);
INSERT INTO epm_gold.gold_acquisition_adjustments
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name, adjustment_type, adjustment_amount, acquisition_date)
VALUES
  ('ZZG', 'ZZE', 2026, 9, 'ZZ4000', 'ZZ revenue', 'pnl_proration', 1100, '2026-12-11'),
  ('ZZG', 'ZZE', 2026, 9, 'ZZ5000', 'ZZ cost', 'pnl_proration', -550, '2026-12-11'),
  ('ZZG', 'ZZE', 2026, 9, 'ZZ3100', 'ZZ retained earnings', 'pnl_proration', -550, '2026-12-11');
