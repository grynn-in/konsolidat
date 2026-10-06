-- assert_hierarchy_all_entities_resolved: must FAIL with exactly 1 result (konsolidat#249).
-- ZZE2 is in the consolidation structure but missing from the ancestry closure, so the
-- tree walk never reaches it. An unmatched LEFT JOIN would read '' for it under
-- join_use_nulls = 0; the NOT IN form must name it. The group's own row ('') is skipped.
INSERT INTO epm_gold.consolidation_groups (consolidation_group, data_area_id, entity_name, reporting_currency)
VALUES ('ZZG', '', 'ZZ Group', 'USD'), ('ZZG', 'ZZE1', 'ZZ One', 'USD'), ('ZZG', 'ZZE2', 'ZZ Two', 'USD');
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path)
VALUES ('ZZG', 'ZZE1', 'ZZG', 'ZZE1', 1, 1, 'ZZG/ZZE1');
