-- assert_hierarchy_all_entities_resolved: must PASS. Both entities reach the group.
INSERT INTO epm_gold.consolidation_groups (consolidation_group, data_area_id, entity_name, reporting_currency)
VALUES ('ZZG', '', 'ZZ Group', 'USD'), ('ZZG', 'ZZE1', 'ZZ One', 'USD'), ('ZZG', 'ZZE2', 'ZZ Two', 'USD');
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path)
VALUES
  ('ZZG', 'ZZE1', 'ZZG', 'ZZE1', 1, 1, 'ZZG/ZZE1'),
  ('ZZG', 'ZZE2', 'ZZG', 'ZZE1', 1, 2, 'ZZG/ZZE1/ZZE2'),
  ('ZZG', 'ZZE2', 'ZZG', 'ZZE2', 2, 2, 'ZZG/ZZE1/ZZE2');
