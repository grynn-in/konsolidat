-- gate: expect assert_ownership_paths_acyclic flag 1
-- konsol#117 shape 6, cross-holding: A holds 70% of B and B holds 10% of A. konsol refuses the
-- second link at validate ("A -> B -> A"); this is the warehouse backstop for a closure row that
-- got in anyway. The path ZZA/ZZB/ZZA visits ZZA twice: one result for the path (its two link
-- rows collapse to one), naming it. The clean path ZZG/ZZE1 is not flagged.
--
-- The live table may predate konsol#117's graph columns: bring the scratch clone to shape.
ALTER TABLE epm_staging.consolidation_ancestry ADD COLUMN IF NOT EXISTS path_id String, ADD COLUMN IF NOT EXISTS link_owner_group String, ADD COLUMN IF NOT EXISTS link_owner_data_area_id String;
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZA', 'ZZA', 'ZZA', 'ZZB', 1, 2, 'ZZA/ZZB/ZZA', 'ZZA/ZZB/ZZA', 'ZZA', 'ZZA'),
  ('ZZA', 'ZZA', 'ZZA', 'ZZA', 2, 2, 'ZZA/ZZB/ZZA', 'ZZA/ZZB/ZZA', 'ZZA', 'ZZB'),
  ('ZZG', 'ZZE1', 'ZZG', 'ZZE1', 1, 1, 'ZZG/ZZE1', 'ZZG/ZZE1', 'ZZG', '');
