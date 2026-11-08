-- assert_tree_node_reached_by_links: must PASS. Tree ZZG > {ZZE1 (entity), ZZS (pure sub-group)}.
-- ZZE1 is reached from its parent ZZG by the path ZZG/ZZE1 (a consolidation_ancestry row for the
-- pair); ZZS is named as the owned node by an Ownership Period. The root has no parent and is
-- not checked.
--
-- The live tables may predate konsol#117's graph columns: bring the scratch clones to shape.
ALTER TABLE epm_staging.consolidation_ancestry ADD COLUMN IF NOT EXISTS path_id String, ADD COLUMN IF NOT EXISTS link_owner_group String, ADD COLUMN IF NOT EXISTS link_owner_data_area_id String;
-- The owner joins the sorting key (konsol#117): two owners of one node from one date are two rows, not one
-- ReplacingMergeTree duplicate. This is the live upgrade statement; it is a no-op on an upgraded table.
ALTER TABLE epm_staging.ownership_periods ADD COLUMN IF NOT EXISTS owner_group String, ADD COLUMN IF NOT EXISTS owner_data_area_id String, MODIFY ORDER BY (consolidation_group, data_area_id, effective_date, owner_group, owner_data_area_id);
INSERT INTO epm_staging.consolidation_hierarchy
  (consolidation_group, data_area_id, parent_group, hierarchy_level, path)
VALUES
  ('ZZG', '',     '',    1, 'ZZG'),
  ('ZZG', 'ZZE1', 'ZZG', 2, 'ZZG/ZZE1'),
  ('ZZS', '',     'ZZG', 2, 'ZZG/ZZS');
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZG', 'ZZE1', 'ZZG', 'ZZE1', 1, 1, 'ZZG/ZZE1', 'ZZG/ZZE1', 'ZZG', '');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id)
VALUES
  ('ZZG', 'ZZE1', '2020-01-01', '2149-06-06', 100, 'full', 'ZZG', ''),
  ('ZZS', '',     '2020-01-01', '2149-06-06', 100, 'full', 'ZZG', '');
