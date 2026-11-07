-- gate: build gold_entity_ownership assert_method_declared_for_multi_path assert_effective_ownership_is_path_sum assert_effective_ownership_in_range
-- gate: expect assert_method_declared_for_multi_path flag 1
-- gate: expect assert_effective_ownership_is_path_sum pass
-- gate: expect assert_effective_ownership_in_range pass
-- konsol#117 shape 2, two members hold a minority: P holds 100% of A and of B (group nodes), and
-- A and B each hold 30% of D at equity. Two paths from P to D, P/A/D 0.30 and P/B/D 0.30:
-- eff(P, D) = 0.60. Both paths' weakest link is equity, neither is all-full, and 60% is above
-- DECLARATION_TRIGGER_PCT (50): the links do not say whether P controls D (IFRS 10) or shares
-- control (IFRS 11), so P must declare. No row in consolidation_method_declarations here:
--   gold_entity_ownership (P, D): method_source 'undeclared', consolidation_method 'none',
--   effective_ownership_pct 0.60 (the sum is still reported), and
--   assert_method_declared_for_multi_path flags exactly that row, naming P, D, 60% and both paths.
-- (A, D) and (B, D) have one path each: equity at 0.30, 'link', not flagged.
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
  ('ZZP', 'ZZB', 'ZZB', 'ZZB', 1, 1, 'ZZP/ZZB',     'ZZP/ZZB',     'ZZP', ''),
  ('ZZP', 'ZZD', 'ZZA', 'ZZA', 1, 2, 'ZZP/ZZA/ZZD', 'ZZP/ZZA/ZZD', 'ZZP', ''),
  ('ZZP', 'ZZD', 'ZZA', 'ZZD', 2, 2, 'ZZP/ZZA/ZZD', 'ZZP/ZZA/ZZD', 'ZZA', 'ZZA'),
  ('ZZP', 'ZZD', 'ZZB', 'ZZB', 1, 2, 'ZZP/ZZA/ZZD', 'ZZP/ZZB/ZZD', 'ZZP', ''),
  ('ZZP', 'ZZD', 'ZZA', 'ZZD', 2, 2, 'ZZP/ZZA/ZZD', 'ZZP/ZZB/ZZD', 'ZZB', 'ZZB'),
  ('ZZA', 'ZZD', 'ZZA', 'ZZD', 1, 1, 'ZZP/ZZA/ZZD', 'ZZA/ZZD',     'ZZA', 'ZZA'),
  ('ZZB', 'ZZD', 'ZZA', 'ZZD', 1, 1, 'ZZP/ZZA/ZZD', 'ZZB/ZZD',     'ZZB', 'ZZB');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id)
VALUES
  ('ZZA', 'ZZA', '2020-01-01', '2149-06-06', 100, 'full',   'ZZP', ''),
  ('ZZB', 'ZZB', '2020-01-01', '2149-06-06', 100, 'full',   'ZZP', ''),
  ('ZZA', 'ZZD', '2020-01-01', '2149-06-06', 30,  'equity', 'ZZA', 'ZZA'),
  ('ZZA', 'ZZD', '2020-01-01', '2149-06-06', 30,  'equity', 'ZZB', 'ZZB');
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZD', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 1000, 0, 1000, 1),
  ('ZZD', 2026, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, 1000, -1000, 1);
