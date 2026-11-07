-- gate: expect assert_effective_ownership_is_path_sum flag 1
-- konsol#117 shape 1, the number the OLD macro produced: one arrayProduct over every link of
-- (ZZP, ZZD) across both paths, 0.80 x 0.60 x 0.20 = 0.096. The oracle sums the paths
-- (0.48 + 0.20 = 0.68), so the seeded gold_entity_ownership row for (ZZP, ZZD) must flag, and
-- only it: (ZZA, ZZD) at 0.60 and (ZZP, ZZA) at 0.80 are right.
--
-- The live tables may predate konsol#117's graph columns: bring the scratch clones to shape.
ALTER TABLE epm_staging.consolidation_ancestry ADD COLUMN IF NOT EXISTS path_id String, ADD COLUMN IF NOT EXISTS link_owner_group String, ADD COLUMN IF NOT EXISTS link_owner_data_area_id String;
-- The owner joins the sorting key (konsol#117): two owners of one node from one date are two rows, not one
-- ReplacingMergeTree duplicate. This is the live upgrade statement; it is a no-op on an upgraded table.
ALTER TABLE epm_staging.ownership_periods ADD COLUMN IF NOT EXISTS owner_group String, ADD COLUMN IF NOT EXISTS owner_data_area_id String, MODIFY ORDER BY (consolidation_group, data_area_id, effective_date, owner_group, owner_data_area_id);
ALTER TABLE epm_gold.gold_entity_ownership ADD COLUMN IF NOT EXISTS path_count UInt32, ADD COLUMN IF NOT EXISTS direct_owner_count UInt32, ADD COLUMN IF NOT EXISTS method_source String;
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
  ('ZZD', 2026, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 1000, -1000, 1),
  ('ZZA', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 10, 0, 10, 1);
INSERT INTO epm_gold.gold_entity_ownership
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, period_date, chain_depth, owner_group,
   has_complete_chain, outside_ownership_window, effective_ownership_pct, direct_ownership_pct, consolidation_method,
   path_count, direct_owner_count, method_source)
VALUES
  ('ZZP', 'ZZA', 2026, 1, '2026-01-01', 1, 'ZZP', 1, 0, 0.8,   0.8, 'full', 1, 1, 'link'),
  ('ZZP', 'ZZD', 2026, 1, '2026-01-01', 2, 'ZZA', 1, 0, 0.096, 0.8, 'full', 2, 2, 'link'),
  ('ZZA', 'ZZD', 2026, 1, '2026-01-01', 1, 'ZZA', 1, 0, 0.6,   0.6, 'full', 1, 1, 'link');
