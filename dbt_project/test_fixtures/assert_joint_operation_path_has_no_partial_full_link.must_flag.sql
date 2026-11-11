-- gate: build gold_entity_ownership assert_joint_operation_path_has_no_partial_full_link assert_effective_ownership_is_path_sum
-- gate: expect assert_joint_operation_path_has_no_partial_full_link flag 1
-- konsol#117 pair 3 review finding A (IFRS 11.20): ZZP holds ZZS at 80% (full), ZZS holds the joint operation ZZJ at
-- 50% (proportional). One path ZZP/ZZS/ZZJ: effective ownership 0.40, weakest link proportional so method proportional,
-- has_partial_full_link 1, has_complete_chain 1. Layer 1 would post 40% of ZZJ's lines with nci 0, where the group
-- should carry 50% with NCI 10%. The sentence is general (finding P): the flag is entity-wide, so it also fires when the partial full link sits on a different path from the proportional one. Expected: the refusal flags 1 row (ZZP, ZZJ, FY2026 P1).
-- The live tables may predate konsol#117's graph columns: bring the scratch clones to the shape the macro reads.
-- The owner joins the sorting key (konsol#117); this is the live upgrade statement, a no-op on an upgraded table.
ALTER TABLE epm_staging.consolidation_ancestry ADD COLUMN IF NOT EXISTS path_id String, ADD COLUMN IF NOT EXISTS link_owner_group String, ADD COLUMN IF NOT EXISTS link_owner_data_area_id String;
ALTER TABLE epm_staging.ownership_periods ADD COLUMN IF NOT EXISTS owner_group String, ADD COLUMN IF NOT EXISTS owner_data_area_id String, MODIFY ORDER BY (consolidation_group, data_area_id, effective_date, owner_group, owner_data_area_id);
CREATE TABLE IF NOT EXISTS epm_staging.consolidation_method_declarations (consolidation_group String, data_area_id String, consolidation_method String, effective_date Date, end_date Date DEFAULT '9999-12-31', reason String, updated_at DateTime DEFAULT now()) ENGINE = ReplacingMergeTree(updated_at) ORDER BY (consolidation_group, data_area_id, effective_date);
-- Nodes: ZZP root (ZZP, ''); ZZS a group node carrying entity ZZS under ZZP (ZZS, 'ZZS'); ZZJ a leaf under ZZS
-- (ZZS, 'ZZJ'). Paths from ZZP to ZZJ: ZZP/ZZS/ZZJ only (links ZZP->ZZS, ZZS->ZZJ).
-- konsolidat#171 / #252: the window is judged on the declared calendar, so the period is declared (a period the
-- calendar does not declare drops out of gold_entity_ownership, and the test could not fail).
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open');
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZP', 'ZZS', 'ZZS', 'ZZS', 1, 1, 'ZZP/ZZS',     'ZZP/ZZS',     'ZZP', ''),
  ('ZZP', 'ZZJ', 'ZZS', 'ZZS', 1, 2, 'ZZP/ZZS/ZZJ', 'ZZP/ZZS/ZZJ', 'ZZP', ''),
  ('ZZP', 'ZZJ', 'ZZS', 'ZZJ', 2, 2, 'ZZP/ZZS/ZZJ', 'ZZP/ZZS/ZZJ', 'ZZS', 'ZZS'),
  ('ZZS', 'ZZJ', 'ZZS', 'ZZJ', 1, 1, 'ZZP/ZZS/ZZJ', 'ZZS/ZZJ',     'ZZS', 'ZZS');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id)
VALUES
  ('ZZS', 'ZZS', '2020-01-01', '2149-06-06', 80, 'full', 'ZZP', ''),
  ('ZZS', 'ZZJ', '2020-01-01', '2149-06-06', 50, 'proportional', 'ZZS', 'ZZS');
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZJ', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 1000, 0, 1000, 1),
  ('ZZJ', 2026, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 1000, -1000, 1);
