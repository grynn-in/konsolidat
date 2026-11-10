-- gate: build gold_entity_ownership assert_effective_ownership_is_path_sum assert_effective_ownership_in_range assert_ownership_chain_complete
-- gate: expect assert_effective_ownership_is_path_sum pass
-- gate: expect assert_effective_ownership_in_range pass
-- gate: expect assert_ownership_chain_complete pass
-- konsolidat#171 / #252 (PR #345 re-review, F1): a step on ONE link dated on the first day of the year.
-- Calendar FY2024 and FY2025, January years, as konsol declares them by default: P0 Opening on 1 January,
-- P1..P12 monthly, P13 Closing and P14 Adjustment on 31 December. konsol closes the current Ownership Period
-- on the day before a change (ownership_change_model: current_ends = effective - 1 day). ZZE uploads FY2024
-- P12 and P14, FY2025 P0 and P1.
-- ZZG holds 60% of ZZE (full) to 2024-12-31 and 80% from 2025-01-01, on the same link.
-- Expected: FY2024 P12 0.60. FY2024 P14 and FY2025 P0 sit on the year boundary (after P12, before P1): ZZE was
-- held on its eve, 31 December, so both are consolidated, read on 1 January at 0.80. FY2025 P1 0.80.
-- On b7db234 both boundary periods read on 31 December, required the link to last to 1 January, found the
-- 60% row (ended 31 December) and dropped them: effective 0.00 (the oracle expects 0.80).
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
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZG', 'ZZE', 'ZZG', 'ZZE', 1, 1, 'ZZG/ZZE', 'ZZG/ZZE', 'ZZG', '');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id)
VALUES
  ('ZZG', 'ZZE', '2020-01-01', '2024-12-31', 60, 'full', 'ZZG', ''),
  ('ZZG', 'ZZE', '2025-01-01', '2149-06-06', 80, 'full', 'ZZG', '');
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZE', 2024, 12, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, 120, 0, 120, 1),
  ('ZZE', 2024, 14, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, 5, 0, 5, 1),
  ('ZZE', 2025, 0, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, 7, 0, 7, 1),
  ('ZZE', 2025, 1, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, 110, 0, 110, 1);
