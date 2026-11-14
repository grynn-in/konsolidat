-- gate: build gold_spread_budget assert_budget_ytd_reconciles assert_budget_fact_grain_unique assert_spread_sums_to_annual
-- gate: expect assert_budget_ytd_reconciles pass
-- gate: expect assert_budget_fact_grain_unique pass
-- gate: expect assert_spread_sums_to_annual pass
-- konsol#348 S2 (R10, Q15-c): epm_raw.budget_entries lines on 'Year-to-date movement' reach
-- gold_spread_budget as period movements, converted within the Cycle year by the rule
-- silver_tb_movements uses (macros/period_movements.sql). One cycle ZZ-CY-2026, scenario ZZ_PLAN_2026,
-- entity ZZE1, FY2026. Net = debit - credit. Stated YTD, and the movements computed by hand:
--
--   layer      account  dims    P1 YTD  P2 YTD  P3 YTD          movements P1 / P2 / P3
--   base       ZZ4000   -       -100    -250    -450 (2 lines)  -100 / -150 / -200
--   base       ZZ6000   ZZCC1     80     200    absent (YTD 0)    80 /  120 / -200
--   challenge  ZZ4000   -       absent    -50     -50              - /  -50 /    0
--
--   * ZZ4000 base P3 is two lines (300 + 150 credit): summed to one YTD of -450 before differencing.
--   * ZZ6000 vanishes in P3: its movement there is -200, the reversal of its P2 YTD. A model that
--     differences only the rows that exist leaves the 200 standing.
--   * The challenge layer is its own series: its first stated period, P2, is its own YTD (-50), not
--     differenced against base. Its P3 movement is 0 and stays as a row (the line exists).
-- assert_budget_ytd_reconciles checks that the running sum of the spread's manual movements equals
-- the stated YTD at every (key, period) above, including 0 for ZZ6000 at P3. On a model that reads only
-- 'Period movement' lines the spread holds none of these rows, and the test names 7 (every stated (key, period) but ZZ6000 at P3, whose stated YTD is 0).
--
-- gold_spread_budget also reads these tables, empty here, so they are named to exist (empty):
-- epm_gold.budget_annual_input, epm_gold.spread_profiles.
--
-- epm_raw.budget_entries is konsol's (I3), declared in clickhouse/init-db.sql: fixture_gate.py creates it
-- (as zzg_raw) when the stack lacks it and adds the fixture budget dimension columns.
INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis, dim_cost_center, dim_department)
VALUES
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 100, 'USD', 'Year-to-date movement', '', ''),
  ('ZZ-BE-2', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 2, 'ZZ4000', 0, 250, 'USD', 'Year-to-date movement', '', ''),
  ('ZZ-BE-3', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 3, 'ZZ4000', 0, 300, 'USD', 'Year-to-date movement', '', ''),
  ('ZZ-BE-3', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 3, 'ZZ4000', 0, 150, 'USD', 'Year-to-date movement', '', ''),
  ('ZZ-BE-1', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 1, 'ZZ6000', 80, 0, 'USD', 'Year-to-date movement', 'ZZCC1', ''),
  ('ZZ-BE-2', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'base', 'ZZE1', 2026, 2, 'ZZ6000', 200, 0, 'USD', 'Year-to-date movement', 'ZZCC1', ''),
  ('ZZ-BE-4', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'challenge', 'ZZE1', 2026, 2, 'ZZ4000', 0, 50, 'USD', 'Year-to-date movement', '', ''),
  ('ZZ-BE-5', 'ZZ-CY-2026', 'ZZ_PLAN_2026', 'challenge', 'ZZE1', 2026, 3, 'ZZ4000', 0, 50, 'USD', 'Year-to-date movement', '', '');
