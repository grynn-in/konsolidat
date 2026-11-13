-- gate: expect assert_budget_basis_supported flag 1
-- konsol#348 S2 (R9): one 'Year-to-date movement' line, which gold_spread_budget does not read (R2 sums
-- 'Period movement' only). The test must name it; the Period movement line beside it must not be flagged.
CREATE TABLE IF NOT EXISTS epm_raw.budget_entries (
    entry_name String, cycle String, scenario_id String, layer String,
    data_area_id String, fiscal_year UInt16, fiscal_period UInt8,
    main_account String, debit Decimal(18,4), credit Decimal(18,4),
    currency String, amount_basis String
) ENGINE = MergeTree
ORDER BY (scenario_id, data_area_id, fiscal_year, fiscal_period, layer, main_account);
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 600, 'USD', 'Period movement'),
  ('ZZ-BE-2', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 3, 'ZZ4000', 0, 1800, 'USD', 'Year-to-date movement');
