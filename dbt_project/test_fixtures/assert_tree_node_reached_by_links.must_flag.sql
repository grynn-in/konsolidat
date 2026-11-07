-- gate: expect assert_tree_node_reached_by_links flag 2
-- assert_tree_node_reached_by_links: must FAIL with exactly 2 results. Tree ZZG > {ZZE1, ZZE2,
-- ZZS, ZZS2}. ZZE1 is reached (ancestry row ZZG/ZZE1) and ZZS is linked (an Ownership Period
-- names it); ZZE2 sits in the tree under ZZG with NO path from ZZG (no ancestry row for the
-- pair) and ZZS2 is a sub-group node no Ownership Period names: both are flagged, by path.
--
-- The live tables may predate konsol#117's graph columns: bring the scratch clones to shape.
ALTER TABLE epm_staging.consolidation_ancestry ADD COLUMN IF NOT EXISTS path_id String, ADD COLUMN IF NOT EXISTS link_owner_group String, ADD COLUMN IF NOT EXISTS link_owner_data_area_id String;
-- The owner joins the sorting key (konsol#117): two owners of one node from one date are two rows, not one
-- ReplacingMergeTree duplicate. This is the live upgrade statement; it is a no-op on an upgraded table.
ALTER TABLE epm_staging.ownership_periods ADD COLUMN IF NOT EXISTS owner_group String, ADD COLUMN IF NOT EXISTS owner_data_area_id String, MODIFY ORDER BY (consolidation_group, data_area_id, effective_date, owner_group, owner_data_area_id);
INSERT INTO epm_staging.consolidation_hierarchy
  (consolidation_group, data_area_id, parent_group, hierarchy_level, path)
VALUES
  ('ZZG',  '',     '',    1, 'ZZG'),
  ('ZZG',  'ZZE1', 'ZZG', 2, 'ZZG/ZZE1'),
  ('ZZG',  'ZZE2', 'ZZG', 2, 'ZZG/ZZE2'),
  ('ZZS',  '',     'ZZG', 2, 'ZZG/ZZS'),
  ('ZZS2', '',     'ZZG', 2, 'ZZG/ZZS2');
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZG', 'ZZE1', 'ZZG', 'ZZE1', 1, 1, 'ZZG/ZZE1', 'ZZG/ZZE1', 'ZZG', '');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id)
VALUES
  ('ZZG', 'ZZE1', '2020-01-01', '2149-06-06', 100, 'full', 'ZZG', ''),
  ('ZZS', '',     '2020-01-01', '2149-06-06', 100, 'full', 'ZZG', '');
