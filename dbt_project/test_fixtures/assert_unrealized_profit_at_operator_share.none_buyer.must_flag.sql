-- konsolidat#336: assert_unrealized_profit_at_operator_share must flag an unrealised-profit row raised for a buyer
-- whose resolved method is 'none' (not line-consolidated). ZZP (100% full) sells to ZZN (method none), inventory 1000,
-- margin 20%. ZZN is not a member, so no row is expected; the seeded row (what the old `!= 'equity'` filter produced) is extra.
-- gate: expect assert_unrealized_profit_at_operator_share flag 1
INSERT INTO epm_gold.gold_entity_ownership
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, effective_ownership_pct, consolidation_method, has_complete_chain)
VALUES
  ('ZZG', 'ZZP', 2026, 1, 1.0, 'full', 1),
  ('ZZG', 'ZZN', 2026, 1, 1.0, 'none', 1);
INSERT INTO epm_staging.ic_elimination_rules
  (rule_id, rule_name, debit_account, credit_account, debit_entity_pattern, credit_entity_pattern, rule_type, margin_pct, asset_account)
VALUES
  ('ZZUP1', 'ZZ unrealised profit', 'ZZ4000', 'ZZ1000', 'ZZP', 'ZZN', 'unrealized_profit', 20, 'ZZ1000');
INSERT INTO epm_staging.ic_balances
  (selling_entity, buying_entity, fiscal_year, fiscal_period, ic_sales_amount, ending_inventory_from_ic)
VALUES
  ('ZZP', 'ZZN', 2026, 1, 1000, 1000);
INSERT INTO epm_gold.gold_ic_eliminations
  (rule_id, rule_name, rule_type, consolidation_group, fiscal_year, fiscal_period, debit_account, credit_account, debit_entity, credit_entity, elimination_amount, debit_elimination, credit_elimination, elimination_kind, difference_cause, basis, elimination_view, entity_a, account_a, entity_b, account_b)
VALUES
  ('ZZUP1', 'ZZ unrealised profit', 'unrealized_profit', 'ZZG', 2026, 1, 'ZZ4000', 'ZZ1000', 'ZZP', 'ZZN', 200, -200, 200, 'unrealized_profit', '', '', 'group', '', '', '', '');
