-- gate: build gold_entity_ownership assert_effective_ownership_is_path_sum assert_effective_ownership_in_range assert_method_declared_for_multi_path assert_ownership_chain_complete assert_ownership_paths_acyclic assert_tree_node_reached_by_links
-- gate: expect assert_effective_ownership_is_path_sum pass
-- gate: expect assert_effective_ownership_in_range pass
-- gate: expect assert_method_declared_for_multi_path pass
-- gate: expect assert_ownership_chain_complete pass
-- gate: expect assert_ownership_paths_acyclic pass
-- gate: expect assert_tree_node_reached_by_links pass
-- konsol#117, the live shape: one chain, four links deep, every link 100% full. The tree
-- ZZG > ZZS1 > ZZS2 > ZZS3 > ZZE, where ZZS1..ZZS3 are group nodes carrying an entity (as
-- three live nodes do) and ZZE is a leaf. Exactly one path from each ancestor to each entity:
-- eff = 1.0 everywhere, NCI 0, method full, path_count 1, method_source 'link'. Pins the upgrade:
-- the graph changes no live number.
--
-- The live tables may predate konsol#117's graph columns and the declarations table: bring the
-- scratch clones to the shape the macro reads.
ALTER TABLE epm_staging.consolidation_ancestry ADD COLUMN IF NOT EXISTS path_id String, ADD COLUMN IF NOT EXISTS link_owner_group String, ADD COLUMN IF NOT EXISTS link_owner_data_area_id String;
-- The owner joins the sorting key (konsol#117): two owners of one node from one date are two rows, not one
-- ReplacingMergeTree duplicate. This is the live upgrade statement; it is a no-op on an upgraded table.
ALTER TABLE epm_staging.ownership_periods ADD COLUMN IF NOT EXISTS owner_group String, ADD COLUMN IF NOT EXISTS owner_data_area_id String, MODIFY ORDER BY (consolidation_group, data_area_id, effective_date, owner_group, owner_data_area_id);
CREATE TABLE IF NOT EXISTS epm_staging.consolidation_method_declarations (consolidation_group String, data_area_id String, consolidation_method String, effective_date Date, end_date Date DEFAULT '9999-12-31', reason String, updated_at DateTime DEFAULT now()) ENGINE = ReplacingMergeTree(updated_at) ORDER BY (consolidation_group, data_area_id, effective_date);
-- konsolidat#171 / #252: the window is judged on the declared calendar, so the period is declared (a period the
-- calendar does not declare drops out of gold_entity_ownership and the oracle, and the test could not fail).
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open');
INSERT INTO epm_staging.consolidation_hierarchy
  (consolidation_group, data_area_id, parent_group, hierarchy_level, path)
VALUES
  ('ZZG',  '',     '',     1, 'ZZG'),
  ('ZZS1', 'ZZS1', 'ZZG',  2, 'ZZG/ZZS1'),
  ('ZZS2', 'ZZS2', 'ZZS1', 3, 'ZZG/ZZS1/ZZS2'),
  ('ZZS3', 'ZZS3', 'ZZS2', 4, 'ZZG/ZZS1/ZZS2/ZZS3'),
  ('ZZS3', 'ZZE',  'ZZS3', 5, 'ZZG/ZZS1/ZZS2/ZZS3/ZZE');
-- The closure konsol's walk writes: one row per (ancestor, entity, link on the path).
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZG',  'ZZS1', 'ZZS1', 'ZZS1', 1, 1, 'ZZG/ZZS1', 'ZZG/ZZS1', 'ZZG', ''),
  ('ZZG',  'ZZS2', 'ZZS1', 'ZZS1', 1, 2, 'ZZG/ZZS1/ZZS2', 'ZZG/ZZS1/ZZS2', 'ZZG', ''),
  ('ZZG',  'ZZS2', 'ZZS2', 'ZZS2', 2, 2, 'ZZG/ZZS1/ZZS2', 'ZZG/ZZS1/ZZS2', 'ZZS1', 'ZZS1'),
  ('ZZS1', 'ZZS2', 'ZZS2', 'ZZS2', 1, 1, 'ZZG/ZZS1/ZZS2', 'ZZS1/ZZS2', 'ZZS1', 'ZZS1'),
  ('ZZG',  'ZZS3', 'ZZS1', 'ZZS1', 1, 3, 'ZZG/ZZS1/ZZS2/ZZS3', 'ZZG/ZZS1/ZZS2/ZZS3', 'ZZG', ''),
  ('ZZG',  'ZZS3', 'ZZS2', 'ZZS2', 2, 3, 'ZZG/ZZS1/ZZS2/ZZS3', 'ZZG/ZZS1/ZZS2/ZZS3', 'ZZS1', 'ZZS1'),
  ('ZZG',  'ZZS3', 'ZZS3', 'ZZS3', 3, 3, 'ZZG/ZZS1/ZZS2/ZZS3', 'ZZG/ZZS1/ZZS2/ZZS3', 'ZZS2', 'ZZS2'),
  ('ZZS1', 'ZZS3', 'ZZS2', 'ZZS2', 1, 2, 'ZZG/ZZS1/ZZS2/ZZS3', 'ZZS1/ZZS2/ZZS3', 'ZZS1', 'ZZS1'),
  ('ZZS1', 'ZZS3', 'ZZS3', 'ZZS3', 2, 2, 'ZZG/ZZS1/ZZS2/ZZS3', 'ZZS1/ZZS2/ZZS3', 'ZZS2', 'ZZS2'),
  ('ZZS2', 'ZZS3', 'ZZS3', 'ZZS3', 1, 1, 'ZZG/ZZS1/ZZS2/ZZS3', 'ZZS2/ZZS3', 'ZZS2', 'ZZS2'),
  ('ZZG',  'ZZE',  'ZZS1', 'ZZS1', 1, 4, 'ZZG/ZZS1/ZZS2/ZZS3/ZZE', 'ZZG/ZZS1/ZZS2/ZZS3/ZZE', 'ZZG', ''),
  ('ZZG',  'ZZE',  'ZZS2', 'ZZS2', 2, 4, 'ZZG/ZZS1/ZZS2/ZZS3/ZZE', 'ZZG/ZZS1/ZZS2/ZZS3/ZZE', 'ZZS1', 'ZZS1'),
  ('ZZG',  'ZZE',  'ZZS3', 'ZZS3', 3, 4, 'ZZG/ZZS1/ZZS2/ZZS3/ZZE', 'ZZG/ZZS1/ZZS2/ZZS3/ZZE', 'ZZS2', 'ZZS2'),
  ('ZZG',  'ZZE',  'ZZS3', 'ZZE',  4, 4, 'ZZG/ZZS1/ZZS2/ZZS3/ZZE', 'ZZG/ZZS1/ZZS2/ZZS3/ZZE', 'ZZS3', 'ZZS3'),
  ('ZZS1', 'ZZE',  'ZZS2', 'ZZS2', 1, 3, 'ZZG/ZZS1/ZZS2/ZZS3/ZZE', 'ZZS1/ZZS2/ZZS3/ZZE', 'ZZS1', 'ZZS1'),
  ('ZZS1', 'ZZE',  'ZZS3', 'ZZS3', 2, 3, 'ZZG/ZZS1/ZZS2/ZZS3/ZZE', 'ZZS1/ZZS2/ZZS3/ZZE', 'ZZS2', 'ZZS2'),
  ('ZZS1', 'ZZE',  'ZZS3', 'ZZE',  3, 3, 'ZZG/ZZS1/ZZS2/ZZS3/ZZE', 'ZZS1/ZZS2/ZZS3/ZZE', 'ZZS3', 'ZZS3'),
  ('ZZS2', 'ZZE',  'ZZS3', 'ZZS3', 1, 2, 'ZZG/ZZS1/ZZS2/ZZS3/ZZE', 'ZZS2/ZZS3/ZZE', 'ZZS2', 'ZZS2'),
  ('ZZS2', 'ZZE',  'ZZS3', 'ZZE',  2, 2, 'ZZG/ZZS1/ZZS2/ZZS3/ZZE', 'ZZS2/ZZS3/ZZE', 'ZZS3', 'ZZS3'),
  ('ZZS3', 'ZZE',  'ZZS3', 'ZZE',  1, 1, 'ZZG/ZZS1/ZZS2/ZZS3/ZZE', 'ZZS3/ZZE', 'ZZS3', 'ZZS3');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id)
VALUES
  ('ZZS1', 'ZZS1', '2020-01-01', '2149-06-06', 100, 'full', 'ZZG',  ''),
  ('ZZS2', 'ZZS2', '2020-01-01', '2149-06-06', 100, 'full', 'ZZS1', 'ZZS1'),
  ('ZZS3', 'ZZS3', '2020-01-01', '2149-06-06', 100, 'full', 'ZZS2', 'ZZS2'),
  ('ZZS3', 'ZZE',  '2020-01-01', '2149-06-06', 100, 'full', 'ZZS3', 'ZZS3');
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZE', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 1000, 0, 1000, 1),
  ('ZZE', 2026, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 1000, -1000, 1);
