-- gate: build gold_entity_ownership assert_effective_ownership_is_path_sum assert_effective_ownership_in_range assert_method_declared_for_multi_path assert_ownership_chain_complete
-- gate: expect assert_effective_ownership_is_path_sum pass
-- gate: expect assert_effective_ownership_in_range pass
-- gate: expect assert_method_declared_for_multi_path pass
-- gate: expect assert_ownership_chain_complete pass
-- konsol#117 shape 5, indirect associate: P holds 100% of A (full), A holds 30% of E (equity).
-- One path P/A/E: eff(P, E) = 0.30, method equity (the weakest link), method_source 'link'.
-- Works today; pinned so the graph keeps it.
--
-- The live tables may predate konsol#117's graph columns and the declarations table: bring the
-- scratch clones to the shape the macro reads.
ALTER TABLE epm_staging.consolidation_ancestry ADD COLUMN IF NOT EXISTS path_id String, ADD COLUMN IF NOT EXISTS link_owner_group String, ADD COLUMN IF NOT EXISTS link_owner_data_area_id String;
-- The owner joins the sorting key (konsol#117): two owners of one node from one date are two rows, not one
-- ReplacingMergeTree duplicate. This is the live upgrade statement; it is a no-op on an upgraded table.
ALTER TABLE epm_staging.ownership_periods ADD COLUMN IF NOT EXISTS owner_group String, ADD COLUMN IF NOT EXISTS owner_data_area_id String, MODIFY ORDER BY (consolidation_group, data_area_id, effective_date, owner_group, owner_data_area_id);
CREATE TABLE IF NOT EXISTS epm_staging.consolidation_method_declarations (consolidation_group String, data_area_id String, consolidation_method String, effective_date Date, end_date Date DEFAULT '9999-12-31', reason String, updated_at DateTime DEFAULT now()) ENGINE = ReplacingMergeTree(updated_at) ORDER BY (consolidation_group, data_area_id, effective_date);
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZP', 'ZZA', 'ZZA', 'ZZA', 1, 1, 'ZZP/ZZA',     'ZZP/ZZA',     'ZZP', ''),
  ('ZZP', 'ZZE', 'ZZA', 'ZZA', 1, 2, 'ZZP/ZZA/ZZE', 'ZZP/ZZA/ZZE', 'ZZP', ''),
  ('ZZP', 'ZZE', 'ZZA', 'ZZE', 2, 2, 'ZZP/ZZA/ZZE', 'ZZP/ZZA/ZZE', 'ZZA', 'ZZA'),
  ('ZZA', 'ZZE', 'ZZA', 'ZZE', 1, 1, 'ZZP/ZZA/ZZE', 'ZZA/ZZE',     'ZZA', 'ZZA');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id)
VALUES
  ('ZZA', 'ZZA', '2020-01-01', '2149-06-06', 100, 'full',   'ZZP', ''),
  ('ZZA', 'ZZE', '2020-01-01', '2149-06-06', 30,  'equity', 'ZZA', 'ZZA');
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZE', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 1000, 0, 1000, 1),
  ('ZZE', 2026, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 1000, -1000, 1);
