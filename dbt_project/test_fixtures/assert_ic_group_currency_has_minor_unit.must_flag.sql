-- gate: expect assert_ic_group_currency_has_minor_unit flag 2
-- konsolidat#395 option B (Deepak Pai, 27 Nov 2026): IC coverage rounds to the group currency's
-- ISO minor unit, so a group with IC eliminations and no minor unit is refused, named with its
-- currency. Three groups, each with one matched balance elimination:
--   ZZG declares ZZX on its root row, and currencies has no ZZX row: flagged (ZZG, ZZX).
--   ZZK has no root row at all: flagged (ZZK, '').
--   ZZH declares EUR, which has a minor unit: not flagged.
INSERT INTO epm_gold.currencies
  (currency_code, currency_name, symbol, minor_unit)
VALUES
  ('EUR', 'Euro', 'E', 2);
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency)
VALUES
  ('ZZG', '', 'ZZ Group G', 'ZZX'),
  ('ZZG', 'ZZE1', 'ZZ Entity 1', 'ZZX'),
  ('ZZH', '', 'ZZ Group H', 'EUR'),
  ('ZZH', 'ZZE1', 'ZZ Entity 1', 'EUR'),
  ('ZZK', 'ZZE1', 'ZZ Entity 1', 'EUR');
INSERT INTO epm_gold.gold_ic_eliminations
  (rule_id, rule_name, rule_type, consolidation_group, fiscal_year, fiscal_period, debit_account, credit_account,
   debit_entity, credit_entity, elimination_amount, debit_elimination, credit_elimination, elimination_kind,
   difference_cause, basis, elimination_view, entity_a, account_a, entity_b, account_b)
VALUES
  ('IC:ZZ1500/ZZ2500', 'Intercompany: matched', 'balance', 'ZZG', 2026, 1, 'ZZ2500', 'ZZ1500', 'ZZE2', 'ZZE1', 100, -100, 100,
   'matched', '', 'balance', 'group', 'ZZE1', 'ZZ1500', 'ZZE2', 'ZZ2500'),
  ('IC:ZZ1500/ZZ2500', 'Intercompany: matched', 'balance', 'ZZH', 2026, 1, 'ZZ2500', 'ZZ1500', 'ZZE2', 'ZZE1', 100, -100, 100,
   'matched', '', 'balance', 'group', 'ZZE1', 'ZZ1500', 'ZZE2', 'ZZ2500'),
  ('IC:ZZ1500/ZZ2500', 'Intercompany: matched', 'balance', 'ZZK', 2026, 1, 'ZZ2500', 'ZZ1500', 'ZZE2', 'ZZE1', 100, -100, 100,
   'matched', '', 'balance', 'group', 'ZZE1', 'ZZ1500', 'ZZE2', 'ZZ2500');
