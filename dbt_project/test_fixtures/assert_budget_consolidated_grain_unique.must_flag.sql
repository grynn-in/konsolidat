-- gate: expect assert_budget_consolidated_grain_unique flag 1
-- assert_budget_consolidated_grain_unique (konsol#348 S4 W8): must FLAG exactly 1 key.
-- gold_fully_consolidated_budget must hold one row per (group, entity, scenario, cycle, layer,
-- year, period, account, adjustment_type, budget dimensions): a reader that windows or sums over
-- that grain (a YTD running total, S5) would otherwise count a key twice.
-- Seeded straight into the model's table (test mode):
--   two 'entity' rows on the SAME key (ZZG, ZZE1, ZZ_PLAN_2026, ZZ-CY-DUP, base, FY2026 P6,
--   ZZ1000, blank dims): the one flagged key;
--   one 'entity' row on the same account under layer 'challenge': a different key, not flagged;
--   one 'cta' row on 'CTA' under base and one 'nci_attribution' row on 'CTA' under base: the same
--   account under two adjustment types is two keys, not flagged.
-- Budget dimensions at the fixture dims are dim_cost_center and dim_department; the live table may
-- have been built at other dims, so they are added by ALTER first.
ALTER TABLE epm_gold.gold_fully_consolidated_budget ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_fully_consolidated_budget ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_fully_consolidated_budget
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name,
   dim_cost_center, dim_department, scenario_id, cycle, layer, reporting_currency, amount, adjustment_type, journal_id)
VALUES
  ('ZZG', 'ZZE1', 2026, 6, 'ZZ1000', 'ZZ cash', '', '', 'ZZ_PLAN_2026', 'ZZ-CY-DUP', 'base', 'USD', 110, 'entity', ''),
  ('ZZG', 'ZZE1', 2026, 6, 'ZZ1000', 'ZZ cash', '', '', 'ZZ_PLAN_2026', 'ZZ-CY-DUP', 'base', 'USD', 110, 'entity', ''),
  ('ZZG', 'ZZE1', 2026, 6, 'ZZ1000', 'ZZ cash', '', '', 'ZZ_PLAN_2026', 'ZZ-CY-DUP', 'challenge', 'USD', 44, 'entity', ''),
  ('ZZG', 'ZZE1', 2026, 6, 'CTA', 'CTA', '', '', 'ZZ_PLAN_2026', 'ZZ-CY-DUP', 'base', 'USD', -5, 'cta', ''),
  ('ZZG', 'ZZE1', 2026, 6, 'CTA', 'CTA', '', '', 'ZZ_PLAN_2026', 'ZZ-CY-DUP', 'base', 'USD', 1, 'nci_attribution', 'NCI-ZZG-ZZE1-2026-P6-ZZ_PLAN_2026-ZZ-CY-DUP-base');
