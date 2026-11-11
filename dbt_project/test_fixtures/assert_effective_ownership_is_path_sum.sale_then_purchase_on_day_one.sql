-- gate: build gold_entity_ownership assert_effective_ownership_is_path_sum assert_effective_ownership_in_range assert_ownership_chain_complete
-- gate: expect assert_effective_ownership_is_path_sum pass
-- gate: expect assert_effective_ownership_in_range pass
-- gate: expect assert_ownership_chain_complete pass
-- konsolidat#171 / #252 (PR #345 round-3 re-review, F2): the group sells ZZE out on the last day of the year and
-- buys it back, through another holding node, on the first day of the next.
-- Calendar FY2024 and FY2025, January years, as konsol declares them by default: P0 Opening on 1 January,
-- P1..P12 monthly, P13 Closing and P14 Adjustment on 31 December. konsol closes the current Ownership Period
-- on the day before a change (ownership_change_model: current_ends = effective - 1 day). ZZE uploads FY2024
-- P12 and P14, FY2025 P0 and P1.
-- ZZE's node is held 60% by ZZA (a sub-group node ZZG holds 100%) until a Business Disposal of ZZE by ZZG dated
-- 2024-12-31 (retained interest 0: the full disposal gold_business_disposal_journal posts in FY2024 P12, line
-- (0) derecognising through P12). On 2025-01-01 ZZB (also held 100%) buys 60% of ZZE: a new acquisition, posted in
-- FY2025 P1.
-- Expected: 0.60 in FY2024 P12; 0 (outside the window) in FY2024 P14 and FY2025 P0, which sit between the
-- disposal period and the acquisition period; 0.60 from FY2025 P1.
-- On 6846fa2 the boundary periods were gated per ENTITY on the eve (ZZA's path, held on 31 December, let them in)
-- and read on 1 January through ZZB: 0.60 (the oracle expects 0).
-- The live tables may predate konsol#117's graph columns: bring the scratch clones to the shape the
-- ownership macro reads.
ALTER TABLE epm_staging.consolidation_ancestry ADD COLUMN IF NOT EXISTS path_id String, ADD COLUMN IF NOT EXISTS link_owner_group String, ADD COLUMN IF NOT EXISTS link_owner_data_area_id String;
ALTER TABLE epm_staging.ownership_periods ADD COLUMN IF NOT EXISTS owner_group String, ADD COLUMN IF NOT EXISTS owner_data_area_id String, MODIFY ORDER BY (consolidation_group, data_area_id, effective_date, owner_group, owner_data_area_id);
CREATE TABLE IF NOT EXISTS epm_staging.consolidation_method_declarations (consolidation_group String, data_area_id String, consolidation_method String, effective_date Date, end_date Date DEFAULT '9999-12-31', reason String, updated_at DateTime DEFAULT now()) ENGINE = ReplacingMergeTree(updated_at) ORDER BY (consolidation_group, data_area_id, effective_date);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2024, 0, 'FY2024-P00', 'FY2024 opening', 'Opening', '2024-01-01', '2024-01-01', '', 'Open'),
  (2024, 1, 'FY2024-P01', 'Jan 2024', 'Regular', '2024-01-01', '2024-01-31', 'Q1', 'Open'),
  (2024, 2, 'FY2024-P02', 'Feb 2024', 'Regular', '2024-02-01', '2024-02-29', 'Q1', 'Open'),
  (2024, 3, 'FY2024-P03', 'Mar 2024', 'Regular', '2024-03-01', '2024-03-31', 'Q1', 'Open'),
  (2024, 4, 'FY2024-P04', 'Apr 2024', 'Regular', '2024-04-01', '2024-04-30', 'Q2', 'Open'),
  (2024, 5, 'FY2024-P05', 'May 2024', 'Regular', '2024-05-01', '2024-05-31', 'Q2', 'Open'),
  (2024, 6, 'FY2024-P06', 'Jun 2024', 'Regular', '2024-06-01', '2024-06-30', 'Q2', 'Open'),
  (2024, 7, 'FY2024-P07', 'Jul 2024', 'Regular', '2024-07-01', '2024-07-31', 'Q3', 'Open'),
  (2024, 8, 'FY2024-P08', 'Aug 2024', 'Regular', '2024-08-01', '2024-08-31', 'Q3', 'Open'),
  (2024, 9, 'FY2024-P09', 'Sep 2024', 'Regular', '2024-09-01', '2024-09-30', 'Q3', 'Open'),
  (2024, 10, 'FY2024-P10', 'Oct 2024', 'Regular', '2024-10-01', '2024-10-31', 'Q4', 'Open'),
  (2024, 11, 'FY2024-P11', 'Nov 2024', 'Regular', '2024-11-01', '2024-11-30', 'Q4', 'Open'),
  (2024, 12, 'FY2024-P12', 'Dec 2024', 'Regular', '2024-12-01', '2024-12-31', 'Q4', 'Open'),
  (2024, 13, 'FY2024-P13', 'FY2024 closing', 'Closing', '2024-12-31', '2024-12-31', '', 'Open'),
  (2024, 14, 'FY2024-P14', 'FY2024 adjustment', 'Adjustment', '2024-12-31', '2024-12-31', '', 'Open'),
  (2025, 0, 'FY2025-P00', 'FY2025 opening', 'Opening', '2025-01-01', '2025-01-01', '', 'Open'),
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
  (2025, 13, 'FY2025-P13', 'FY2025 closing', 'Closing', '2025-12-31', '2025-12-31', '', 'Open'),
  (2025, 14, 'FY2025-P14', 'FY2025 adjustment', 'Adjustment', '2025-12-31', '2025-12-31', '', 'Open');
CREATE TABLE IF NOT EXISTS epm_staging.business_disposals (name String, consolidation_group String, disposed_entity String, disposal_date Date, share_disposed_pct Float64, retained_interest_pct Float64, proceeds_currency String, total_proceeds Float64, ownership_period String) ENGINE = MergeTree ORDER BY name;
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZG', 'ZZA', 'ZZA', 'ZZA', 1, 1, 'ZZG/ZZA', 'ZZG/ZZA', 'ZZG', ''),
  ('ZZG', 'ZZE', 'ZZA', 'ZZA', 1, 2, 'ZZG/ZZA/ZZE', 'ZZG/ZZA/ZZE', 'ZZG', ''),
  ('ZZG', 'ZZE', 'ZZG', 'ZZE', 2, 2, 'ZZG/ZZA/ZZE', 'ZZG/ZZA/ZZE', 'ZZA', 'ZZA'),
  ('ZZG', 'ZZB', 'ZZB', 'ZZB', 1, 1, 'ZZG/ZZB', 'ZZG/ZZB', 'ZZG', ''),
  ('ZZG', 'ZZE', 'ZZB', 'ZZB', 1, 2, 'ZZG/ZZB/ZZE', 'ZZG/ZZB/ZZE', 'ZZG', ''),
  ('ZZG', 'ZZE', 'ZZG', 'ZZE', 2, 2, 'ZZG/ZZB/ZZE', 'ZZG/ZZB/ZZE', 'ZZB', 'ZZB');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id, is_disposal, disposal_date)
VALUES
  ('ZZA', 'ZZA', '2020-01-01', '2149-06-06', 100, 'full', 'ZZG', '', 0, '2149-06-06'),
  ('ZZB', 'ZZB', '2020-01-01', '2149-06-06', 100, 'full', 'ZZG', '', 0, '2149-06-06'),
  ('ZZG', 'ZZE', '2020-01-01', '2024-12-31', 60, 'full', 'ZZA', 'ZZA', 1, '2024-12-31'),
  ('ZZG', 'ZZE', '2025-01-01', '2149-06-06', 60, 'full', 'ZZB', 'ZZB', 0, '2149-06-06');
INSERT INTO epm_staging.business_disposals
  (name, consolidation_group, disposed_entity, disposal_date, share_disposed_pct, retained_interest_pct, proceeds_currency, total_proceeds, ownership_period)
VALUES
  ('BD-ZZG-ZZE-2024-12-31', 'ZZG', 'ZZE', '2024-12-31', 60, 0, 'USD', 1000, 'ZZ-OP-ZZE-1');
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZE', 2024, 12, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, 120, 0, 120, 1),
  ('ZZE', 2024, 14, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, 5, 0, 5, 1),
  ('ZZE', 2025, 0, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, 7, 0, 7, 1),
  ('ZZE', 2025, 1, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, 110, 0, 110, 1);
