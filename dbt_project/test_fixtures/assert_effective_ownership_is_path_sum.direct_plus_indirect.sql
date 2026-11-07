-- gate: build gold_entity_ownership assert_effective_ownership_is_path_sum assert_effective_ownership_in_range assert_method_declared_for_multi_path assert_ownership_chain_complete
-- gate: expect assert_effective_ownership_is_path_sum pass
-- gate: expect assert_effective_ownership_in_range pass
-- gate: expect assert_method_declared_for_multi_path pass
-- gate: expect assert_ownership_chain_complete pass
-- konsol#117 shape 1, direct plus indirect: P holds 80% of A (a sub-group node), A holds 60% of D,
-- and P holds 20% of D directly. Two paths from P to D:
--   P/A/D: 0.80 x 0.60 = 0.48      P/D: 0.20      eff(P, D) = 0.68, NCI 0.32
--   eff(A, D) = 0.60 (one path). Both paths' weakest link is full and P/A/D is all-full: method
--   full, derived from the links (method_source 'link'), no declaration needed.
-- D's profit of 1,000 at P: group 680 / NCI 320 (nci = 1 - eff downstream; not built here).
-- gold_entity_ownership is BUILT from these staging rows; the oracle test recomputes each path
-- as exp(sum(log(pct))) and sums. Before konsol#117 the macro multiplied every link of (P, D)
-- into one product, 0.096 — the .must_flag fixture seeds that number.
--
-- The live tables may predate konsol#117's graph columns and the declarations table: bring the
-- scratch clones to the shape the macro reads (konsol's ensure_reference_tables does this live).
ALTER TABLE epm_staging.consolidation_ancestry ADD COLUMN IF NOT EXISTS path_id String, ADD COLUMN IF NOT EXISTS link_owner_group String, ADD COLUMN IF NOT EXISTS link_owner_data_area_id String;
-- The owner joins the sorting key (konsol#117): two owners of one node from one date are two rows, not one
-- ReplacingMergeTree duplicate. This is the live upgrade statement; it is a no-op on an upgraded table.
ALTER TABLE epm_staging.ownership_periods ADD COLUMN IF NOT EXISTS owner_group String, ADD COLUMN IF NOT EXISTS owner_data_area_id String, MODIFY ORDER BY (consolidation_group, data_area_id, effective_date, owner_group, owner_data_area_id);
CREATE TABLE IF NOT EXISTS epm_staging.consolidation_method_declarations (consolidation_group String, data_area_id String, consolidation_method String, effective_date Date, end_date Date DEFAULT '9999-12-31', reason String, updated_at DateTime DEFAULT now()) ENGINE = ReplacingMergeTree(updated_at) ORDER BY (consolidation_group, data_area_id, effective_date);
-- Nodes: ZZP root (ZZP, ''); ZZA a group node carrying entity ZZA under ZZP (ZZA, 'ZZA');
-- ZZD a leaf under ZZA (ZZA, 'ZZD'). A leaf's consolidation_group is its parent's code.
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZP', 'ZZA', 'ZZA', 'ZZA', 1, 1, 'ZZP/ZZA',     'ZZP/ZZA',     'ZZP', ''),
  ('ZZP', 'ZZD', 'ZZA', 'ZZA', 1, 2, 'ZZP/ZZA/ZZD', 'ZZP/ZZA/ZZD', 'ZZP', ''),
  ('ZZP', 'ZZD', 'ZZA', 'ZZD', 2, 2, 'ZZP/ZZA/ZZD', 'ZZP/ZZA/ZZD', 'ZZA', 'ZZA'),
  ('ZZP', 'ZZD', 'ZZA', 'ZZD', 1, 1, 'ZZP/ZZA/ZZD', 'ZZP/ZZD',     'ZZP', ''),
  ('ZZA', 'ZZD', 'ZZA', 'ZZD', 1, 1, 'ZZP/ZZA/ZZD', 'ZZA/ZZD',     'ZZA', 'ZZA');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id)
VALUES
  ('ZZA', 'ZZA', '2020-01-01', '2149-06-06', 80, 'full', 'ZZP', ''),
  ('ZZA', 'ZZD', '2020-01-01', '2149-06-06', 60, 'full', 'ZZA', 'ZZA'),
  ('ZZA', 'ZZD', '2020-01-01', '2149-06-06', 20, 'full', 'ZZP', '');
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZD', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 1000, 0, 1000, 1),
  ('ZZD', 2026, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 1000, -1000, 1);
