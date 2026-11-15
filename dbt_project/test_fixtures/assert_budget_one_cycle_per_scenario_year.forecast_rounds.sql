-- konsol#348 S3 B5 (QB8 a): only a forecast scenario has rounds, and each round is its own approved
-- Cycle (Q23 a), so a forecast (scenario, fiscal year) holds lines under several cycles BY DESIGN.
-- Scenario ZZ_FC_2026 is declared scenario_type 'forecast' and FY2026 has lines in cycles ZZ-FC-R1 and
-- ZZ-FC-R2 on the same account: not named. Must PASS. On the S2 test, which checked every scenario,
-- it is named (1 result).
-- The budget-type backstop is unchanged: assert_budget_one_cycle_per_scenario_year.must_flag.sql.
-- Until S6 the forecast side is assert_forecast_one_approved_round_until_s6, which names this same
-- data on gold_spread_budget (interim rule on konsol#348, 15 Nov 2026): two approved rounds may not
-- coexist yet, because the readers sum them. That is its gate, not this one.
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ZZ_FC_2026', 'ZZ forecast 2026', 'forecast', 1);

INSERT INTO epm_raw.budget_entries
  (entry_name, cycle, scenario_id, layer, data_area_id, fiscal_year, fiscal_period, main_account, debit, credit, currency, amount_basis)
VALUES
  ('ZZ-BE-R1', 'ZZ-FC-R1', 'ZZ_FC_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 100, 'USD', 'Period movement'),
  ('ZZ-BE-R2', 'ZZ-FC-R2', 'ZZ_FC_2026', 'base', 'ZZE1', 2026, 1, 'ZZ4000', 0, 110, 'USD', 'Period movement');
