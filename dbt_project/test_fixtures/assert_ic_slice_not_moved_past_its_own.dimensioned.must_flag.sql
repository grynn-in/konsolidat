-- gate: expect assert_ic_slice_not_moved_past_its_own flag 1
-- konsolidat#245 F2 (PR #260 review). The test's final WHERE rendered, with two or more declared dimensions, as
--   e.d1 != '' or e.d2 != '' or e.d3 != '' and e.moved > own + floor
-- and AND binds tighter than OR, so every sliced row with d1 or d2 set failed whatever it moved. The fixture declares
-- three dimensions (FIXTURE_DIMENSIONS). Two cost centres on an intercompany receivable/payable pair, A (+60 / +40)
-- and B (-60 / -40):
--   wrong elimination: ZZ-CC1 on the receivable is -100 against the 60 it booked: exactly one row must flag
--   (the base flagged all four).
INSERT INTO epm_gold.gold_ic_side_slices
(consolidation_group, fiscal_year, fiscal_period, entity, partner, account, counterpart,
dim_business_unit, dim_cost_center, dim_department, mov_local, mov_translated, mov_group)
VALUES
('ZZG', 2026, 6, 'ZZA', 'ZZB', 'ZZ1100', 'ZZ2100', '', 'ZZ-CC1', '',  60,  60,  60),
('ZZG', 2026, 6, 'ZZA', 'ZZB', 'ZZ1100', 'ZZ2100', '', 'ZZ-CC2', '',  40,  40,  40),
('ZZG', 2026, 6, 'ZZB', 'ZZA', 'ZZ2100', 'ZZ1100', '', 'ZZ-CC1', '', -60, -60, -60),
('ZZG', 2026, 6, 'ZZB', 'ZZA', 'ZZ2100', 'ZZ1100', '', 'ZZ-CC2', '', -40, -40, -40);
INSERT INTO epm_gold.gold_fully_consolidated_tb
(consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name,
dim_business_unit, dim_cost_center, dim_department, reporting_currency, amount, adjustment_type, journal_id)
VALUES
('ZZG', '', 2026, 6, 'ZZ1100', 'IC Elimination', '', 'ZZ-CC1', '', '', -100, 'ic_elimination', 'IC:ZZ1100/ZZ2100'),
('ZZG', '', 2026, 6, 'ZZ1100', 'IC Elimination', '', 'ZZ-CC2', '', '', -40, 'ic_elimination', 'IC:ZZ1100/ZZ2100'),
('ZZG', '', 2026, 6, 'ZZ2100', 'IC Elimination', '', 'ZZ-CC1', '', '',  60, 'ic_elimination', 'IC:ZZ1100/ZZ2100'),
('ZZG', '', 2026, 6, 'ZZ2100', 'IC Elimination', '', 'ZZ-CC2', '', '',  40, 'ic_elimination', 'IC:ZZ1100/ZZ2100');
