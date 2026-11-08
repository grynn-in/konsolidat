-- konsol#117 pair 3 review finding E: assert_unrealized_profit_at_operator_share must flag a MISSING model row.
-- Staging rule and balance exist and gold_entity_ownership has the buyer (50% proportional), but gold_ic_eliminations
-- has no unrealized_profit row: expected 100, the model has nothing.
-- gate: expect assert_unrealized_profit_at_operator_share flag 1
INSERT INTO epm_gold.gold_entity_ownership
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, effective_ownership_pct, consolidation_method, has_complete_chain)
VALUES
  ('ZZG', 'ZZP', 2026, 1, 1.0, 'full', 1),
  ('ZZG', 'ZZJ', 2026, 1, 0.5, 'proportional', 1);
INSERT INTO epm_staging.ic_elimination_rules
  (rule_id, rule_name, debit_account, credit_account, debit_entity_pattern, credit_entity_pattern, rule_type, margin_pct, asset_account)
VALUES
  ('ZZUP1', 'ZZ unrealised profit', 'ZZ4000', 'ZZ1000', 'ZZP', 'ZZJ', 'unrealized_profit', 20, 'ZZ1000');
INSERT INTO epm_staging.ic_balances
  (selling_entity, buying_entity, fiscal_year, fiscal_period, ic_sales_amount, ending_inventory_from_ic)
VALUES
  ('ZZP', 'ZZJ', 2026, 1, 1000, 1000);
