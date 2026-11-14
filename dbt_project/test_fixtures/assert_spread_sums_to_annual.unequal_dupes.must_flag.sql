-- gate: build gold_spread_budget assert_spread_sums_to_annual
-- gate: expect assert_spread_sums_to_annual flag 1
-- Two annual inputs for one grain with different amounts (1200 and 600, ZZ_PLAN_2026 / ZZE1 / 2026 / ZZ4000) are
-- both spread: 1800 against an annual_amount of 1200 at most. The test must FLAG 1 for the grain.
-- epm_raw.budget_entries is konsol's (I3) and may not exist on the stack yet: created here as in budget_raw_monthly.
CREATE TABLE IF NOT EXISTS epm_raw.budget_entries (
    entry_name String, cycle String, scenario_id String, layer String,
    data_area_id String, fiscal_year UInt16, fiscal_period UInt8,
    main_account String, debit Decimal(18,4), credit Decimal(18,4),
    currency String, amount_basis String
) ENGINE = MergeTree
ORDER BY (scenario_id, data_area_id, fiscal_year, fiscal_period, layer, main_account);
ALTER TABLE epm_raw.budget_entries ADD COLUMN IF NOT EXISTS dim_cost_center String DEFAULT '';
ALTER TABLE epm_raw.budget_entries ADD COLUMN IF NOT EXISTS dim_department String DEFAULT '';
INSERT INTO epm_gold.budget_annual_input
  (scenario_id, data_area_id, fiscal_year, main_account, annual_amount, spread_profile_id, submitted_by)
VALUES
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4000', 1200, 'ZZ_FLAT', 'zz'),
  ('ZZ_PLAN_2026', 'ZZE1', 2026, 'ZZ4000', 600, 'ZZ_FLAT', 'zz');
INSERT INTO epm_gold.spread_profiles (profile_id, profile_name, fiscal_period, weight) VALUES
  ('ZZ_FLAT', 'ZZ flat', 1, 1), ('ZZ_FLAT', 'ZZ flat', 2, 1), ('ZZ_FLAT', 'ZZ flat', 3, 1), ('ZZ_FLAT', 'ZZ flat', 4, 1),
  ('ZZ_FLAT', 'ZZ flat', 5, 1), ('ZZ_FLAT', 'ZZ flat', 6, 1), ('ZZ_FLAT', 'ZZ flat', 7, 1), ('ZZ_FLAT', 'ZZ flat', 8, 1),
  ('ZZ_FLAT', 'ZZ flat', 9, 1), ('ZZ_FLAT', 'ZZ flat', 10, 1), ('ZZ_FLAT', 'ZZ flat', 11, 1), ('ZZ_FLAT', 'ZZ flat', 12, 1);
