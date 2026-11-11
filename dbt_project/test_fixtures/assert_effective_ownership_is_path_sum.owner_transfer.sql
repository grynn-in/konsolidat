-- gate: build gold_entity_ownership assert_effective_ownership_is_path_sum assert_effective_ownership_in_range assert_ownership_chain_complete
-- gate: expect assert_effective_ownership_is_path_sum pass
-- gate: expect assert_effective_ownership_in_range pass
-- gate: expect assert_ownership_chain_complete pass
-- konsolidat#171 / #252 (PR #345 review, finding 1): a holding that moves between two owners INSIDE a period
-- counts once, under the owner that holds it at the period end. Calendar FY2025, monthly from January. ZZE's node
-- is held 60% by ZZA and 40% by ZZC; on 2025-06-15 ZZA's 60% passes to ZZB (ZZA's link ends 2025-06-14, ZZB's
-- starts 2025-06-15). ZZA, ZZB and ZZC are sub-group nodes ZZG holds 100%. ZZE uploads P5, P6 and P7.
-- Expected: ZZG's effective share of ZZE is 1.00 in every period (P6: ZZB 0.60 + ZZC 0.40).
-- Before: a link stayed in the window while its end date was on or after the period START, so in P6 both
-- ZZA's and ZZB's links resolved: 0.60 + 0.60 + 0.40 = 1.60 (assert_effective_ownership_in_range, and the
-- path-sum oracle, which reads each link at the period end, expects 1.00).
-- The live tables may predate konsol#117's graph columns: bring the scratch clones to the shape the
-- ownership macro reads.
ALTER TABLE epm_staging.consolidation_ancestry ADD COLUMN IF NOT EXISTS path_id String, ADD COLUMN IF NOT EXISTS link_owner_group String, ADD COLUMN IF NOT EXISTS link_owner_data_area_id String;
ALTER TABLE epm_staging.ownership_periods ADD COLUMN IF NOT EXISTS owner_group String, ADD COLUMN IF NOT EXISTS owner_data_area_id String, MODIFY ORDER BY (consolidation_group, data_area_id, effective_date, owner_group, owner_data_area_id);
CREATE TABLE IF NOT EXISTS epm_staging.consolidation_method_declarations (consolidation_group String, data_area_id String, consolidation_method String, effective_date Date, end_date Date DEFAULT '9999-12-31', reason String, updated_at DateTime DEFAULT now()) ENGINE = ReplacingMergeTree(updated_at) ORDER BY (consolidation_group, data_area_id, effective_date);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2025, 1, 'FY2025-P01', 'Jan 2025', 'Regular', '2025-01-01', '2025-01-31', 'Q1', 'Open'),
  (2025, 2, 'FY2025-P02', 'Feb 2025', 'Regular', '2025-02-01', '2025-02-28', 'Q1', 'Open'),
  (2025, 3, 'FY2025-P03', 'Mar 2025', 'Regular', '2025-03-01', '2025-03-31', 'Q1', 'Open'),
  (2025, 4, 'FY2025-P04', 'Apr 2025', 'Regular', '2025-04-01', '2025-04-30', 'Q2', 'Open'),
  (2025, 5, 'FY2025-P05', 'May 2025', 'Regular', '2025-05-01', '2025-05-31', 'Q2', 'Open'),
  (2025, 6, 'FY2025-P06', 'Jun 2025', 'Regular', '2025-06-01', '2025-06-30', 'Q2', 'Open'),
  (2025, 7, 'FY2025-P07', 'Jul 2025', 'Regular', '2025-07-01', '2025-07-31', 'Q3', 'Open'),
  (2025, 8, 'FY2025-P08', 'Aug 2025', 'Regular', '2025-08-01', '2025-08-31', 'Q3', 'Open'),
  (2025, 9, 'FY2025-P09', 'Sep 2025', 'Regular', '2025-09-01', '2025-09-30', 'Q3', 'Open'),
  (2025, 10, 'FY2025-P10', 'Oct 2025', 'Regular', '2025-10-01', '2025-10-31', 'Q4', 'Open'),
  (2025, 11, 'FY2025-P11', 'Nov 2025', 'Regular', '2025-11-01', '2025-11-30', 'Q4', 'Open'),
  (2025, 12, 'FY2025-P12', 'Dec 2025', 'Regular', '2025-12-01', '2025-12-31', 'Q4', 'Open'),
  (2025, 13, 'FY2025-P13', 'FY2025 closing', 'Closing', '2025-12-31', '2025-12-31', '', 'Open');
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZG', 'ZZA', 'ZZA', 'ZZA', 1, 1, 'ZZG/ZZA', 'ZZG/ZZA', 'ZZG', ''),
  ('ZZG', 'ZZE', 'ZZA', 'ZZA', 1, 2, 'ZZG/ZZA/ZZE', 'ZZG/ZZA/ZZE', 'ZZG', ''),
  ('ZZG', 'ZZE', 'ZZG', 'ZZE', 2, 2, 'ZZG/ZZA/ZZE', 'ZZG/ZZA/ZZE', 'ZZA', 'ZZA'),
  ('ZZG', 'ZZB', 'ZZB', 'ZZB', 1, 1, 'ZZG/ZZB', 'ZZG/ZZB', 'ZZG', ''),
  ('ZZG', 'ZZE', 'ZZB', 'ZZB', 1, 2, 'ZZG/ZZB/ZZE', 'ZZG/ZZB/ZZE', 'ZZG', ''),
  ('ZZG', 'ZZE', 'ZZG', 'ZZE', 2, 2, 'ZZG/ZZB/ZZE', 'ZZG/ZZB/ZZE', 'ZZB', 'ZZB'),
  ('ZZG', 'ZZC', 'ZZC', 'ZZC', 1, 1, 'ZZG/ZZC', 'ZZG/ZZC', 'ZZG', ''),
  ('ZZG', 'ZZE', 'ZZC', 'ZZC', 1, 2, 'ZZG/ZZC/ZZE', 'ZZG/ZZC/ZZE', 'ZZG', ''),
  ('ZZG', 'ZZE', 'ZZG', 'ZZE', 2, 2, 'ZZG/ZZC/ZZE', 'ZZG/ZZC/ZZE', 'ZZC', 'ZZC');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id)
VALUES
  ('ZZA', 'ZZA', '2020-01-01', '2149-06-06', 100, 'full', 'ZZG', ''),
  ('ZZB', 'ZZB', '2020-01-01', '2149-06-06', 100, 'full', 'ZZG', ''),
  ('ZZC', 'ZZC', '2020-01-01', '2149-06-06', 100, 'full', 'ZZG', ''),
  ('ZZG', 'ZZE', '2020-01-01', '2025-06-14', 60, 'full', 'ZZA', 'ZZA'),
  ('ZZG', 'ZZE', '2025-06-15', '2149-06-06', 60, 'full', 'ZZB', 'ZZB'),
  ('ZZG', 'ZZE', '2020-01-01', '2149-06-06', 40, 'full', 'ZZC', 'ZZC');
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZE', 2025, 5, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, 50, 0, 50, 1),
  ('ZZE', 2025, 6, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, 60, 0, 60, 1),
  ('ZZE', 2025, 7, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, 70, 0, 70, 1);
