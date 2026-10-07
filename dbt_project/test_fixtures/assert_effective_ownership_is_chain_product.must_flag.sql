-- assert_effective_ownership_is_chain_product: must FAIL with exactly 1 result (konsolidat#249).
--
-- ZZE2 is held 50% by ZZE1, which the group holds 80%: the chain product is 0.40. The
-- seeded gold_entity_ownership says 0.50 (the direct link only), so the test must flag it.
-- ZZE3 has an ancestry link with NO ownership row: the oracle's ASOF LEFT JOIN leaves it
-- unmatched. ownership_pct is cast to Nullable(Float64) before the join, so the unmatched
-- value is NULL even under join_use_nulls = 0, unresolved > 0, and ZZE3 is skipped (its
-- missing link is assert_ownership_chain_complete's job). Were the cast removed, the
-- unmatched pct would be 0, zero_links would skip it too, and ZZE3 must still not be flagged.
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl,
   dim_business_unit, dim_cost_center, dim_department, period_credit, period_debit, period_net_amount, transaction_count)
VALUES
  ('ZZE2', 2026, 1, 'ZZ1000', 'cash', 'Asset', 1, 0, '', '', '', 0, 100, 100, 1);
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path)
VALUES
  ('ZZG', 'ZZE1', 'ZZG', 'ZZE1', 1, 1, 'ZZG/ZZE1'),
  ('ZZG', 'ZZE2', 'ZZG', 'ZZE1', 1, 2, 'ZZG/ZZE1/ZZE2'),
  ('ZZG', 'ZZE2', 'ZZG', 'ZZE2', 2, 2, 'ZZG/ZZE1/ZZE2'),
  ('ZZG', 'ZZE3', 'ZZG', 'ZZE3', 1, 1, 'ZZG/ZZE3');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method)
VALUES
  ('ZZG', 'ZZE1', '2020-01-01', '2149-06-06', 80, 'full'),
  ('ZZG', 'ZZE2', '2020-01-01', '2149-06-06', 50, 'full');
INSERT INTO epm_gold.gold_entity_ownership
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, period_date, chain_depth, owner_group,
   has_complete_chain, outside_ownership_window, effective_ownership_pct, direct_ownership_pct, consolidation_method)
VALUES
  ('ZZG', 'ZZE1', 2026, 1, '2026-01-31', 1, 'ZZG', 1, 0, 0.8, 0.8, 'full'),
  ('ZZG', 'ZZE2', 2026, 1, '2026-01-31', 2, 'ZZG', 1, 0, 0.5, 0.5, 'full'),
  ('ZZG', 'ZZE3', 2026, 1, '2026-01-31', 1, 'ZZG', 0, 0, 0.3, 0.3, 'full');
