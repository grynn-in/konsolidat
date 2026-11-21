-- gate: expect assert_ic_difference_on_the_blank_slice flag 1
-- konsolidat#245 Q1 A (Deepak Pai, 21 Nov 2026): the intercompany difference entry sits on the blank slice
-- on both legs. Rows seeded straight into the two relations the test reads, as layer 2 posted them before
-- the decision. Balance pair ZZ1100/ZZ2100: ZZA receivable +100 (ZZ-CC1 60, ZZ-CC2 40) against ZZB payable
-- -90 (ZZ-CC9). Matched 90; the difference 10 goes to ZZ1900. Layer 2 split the IC-account difference leg
-- -10 over ZZ-CC1 / ZZ-CC2 (-6 / -4) beside the matched -54 / -36, so ZZ1100 carries -100 on its slices
-- against a matched allowance of 90: one row flags (ZZ1100, 2026 P1). ZZ2100 (+90 against 90) and the
-- blank ZZ1900 leg do not.
INSERT INTO epm_gold.gold_ic_eliminations
(rule_id, rule_name, rule_type, consolidation_group, fiscal_year, fiscal_period, debit_account, credit_account,
debit_entity, credit_entity, elimination_amount, debit_elimination, credit_elimination, elimination_kind,
difference_cause, basis, elimination_view, entity_a, account_a, entity_b, account_b)
VALUES
('IC:ZZ1100/ZZ2100', 'Intercompany: matched', 'balance', 'ZZG', 2026, 1, 'ZZ1100', 'ZZ2100',
 'ZZA', 'ZZB', 90, -90, 90, 'matched', '', 'balance', 'group', 'ZZA', 'ZZ1100', 'ZZB', 'ZZ2100'),
('IC:ZZ1100/ZZ2100', 'Intercompany: difference', 'balance', 'ZZG', 2026, 1, 'ZZ1100', 'ZZ1900',
 'ZZA', 'ZZB', 10, -10, 10, 'difference', 'booking', 'balance', 'group', 'ZZA', 'ZZ1100', 'ZZB', 'ZZ2100');
INSERT INTO epm_gold.gold_fully_consolidated_tb
(consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name,
dim_business_unit, dim_cost_center, dim_department, reporting_currency, amount, adjustment_type, journal_id)
VALUES
('ZZG', '', 2026, 1, 'ZZ1100', 'IC Elimination', '', 'ZZ-CC1', '', '', -54, 'ic_elimination', 'IC:ZZ1100/ZZ2100'),
('ZZG', '', 2026, 1, 'ZZ1100', 'IC Elimination', '', 'ZZ-CC2', '', '', -36, 'ic_elimination', 'IC:ZZ1100/ZZ2100'),
('ZZG', '', 2026, 1, 'ZZ1100', 'IC Elimination', '', 'ZZ-CC1', '', '',  -6, 'ic_elimination', 'IC:ZZ1100/ZZ2100'),
('ZZG', '', 2026, 1, 'ZZ1100', 'IC Elimination', '', 'ZZ-CC2', '', '',  -4, 'ic_elimination', 'IC:ZZ1100/ZZ2100'),
('ZZG', '', 2026, 1, 'ZZ2100', 'IC Elimination', '', 'ZZ-CC9', '', '',  90, 'ic_elimination', 'IC:ZZ1100/ZZ2100'),
('ZZG', '', 2026, 1, 'ZZ1900', 'IC Elimination', '', '', '', '',        10, 'ic_elimination', 'IC:ZZ1100/ZZ2100');
