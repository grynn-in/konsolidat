-- gate: build gold_forecast_accuracy_group assert_forecast_accuracy_group_hand_table
-- gate: expect gold_forecast_accuracy_group built
-- gate: expect assert_forecast_accuracy_group_hand_table pass
-- konsol#348 S6 WC3 (FC-4-2, S6-Q8 a): forecast accuracy in group currency, worked by hand. FY2026
-- P1-P12 declared (Regular, monthly); P1-P4 Closed, P5-P12 Open. Forecast scenario ZZ_FC_ACG has one
-- approved round ZZ-ACG-R1 as of 2026-03-31 (P3), horizon 3; budget scenario ZZ_PLAN_ACG's Cycle is not a
-- round. gold_consolidated_budget_tb and gold_consolidated_trial_balance are seeded directly (their own
-- fixtures prove the translation); the group is USD.
--   Budget (R1): ZZG ZZE1 (USD) P4 ZZ4000 base -45 + challenge -5, ZZ5000 20; ZZG ZZE2 (EUR) P4 ZZ4000
--   local -100 at the budget set's 1.1 -> -110; ZZG2 ZZE1 (proportional 50%) P4 ZZ4000 -25; ZZE1 P3 -30
--   (the as-of period) and P5 -60 (Open): not measured; ZZ_PLAN_ACG's -999: not a round.
--   Actuals: ZZG ZZE1 P4 ZZ4000 -40, ZZ6000 8 (no forecast: a forecast of 0); ZZG ZZE2 P4 ZZ4000 local
--   -100 at the actuals' 1.2 -> -120; ZZG ZZE3 P4 -7 (no round forecasts ZZE3 in ZZG: absent); ZZG ZZE1
--   P5 -61 (Open); ZZG2 ZZE1 P4 ZZ4000 -20.
-- Expected, in assert_forecast_accuracy_group_hand_table: ZZG ZZE1 ZZ4000 -50 vs -40, ZZ5000 20 vs 0
-- (error % NULL), ZZ6000 0 vs 8; ZZG ZZE2 ZZ4000 -110 vs -120 (error 10, the FX movement); ZZG2 ZZE1
-- ZZ4000 -25 vs -20. Red before WC3: the model does not exist.
-- Budget dimensions at the fixture dims are dim_cost_center and dim_department; the live tables may have
-- been built at other dims, so they are added by ALTER first.
INSERT INTO epm_gold.scenario_definitions
  (scenario_id, scenario_name, scenario_type, is_active)
VALUES
  ('ZZ_ACT', 'ZZ actual', 'actual', 1),
  ('ZZ_FC_ACG', 'ZZ forecast', 'forecast', 1),
  ('ZZ_PLAN_ACG', 'ZZ plan', 'budget', 1);
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 1, 'FY2026-P01', 'P01 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Closed'),
  (2026, 2, 'FY2026-P02', 'P02 2026', 'Regular', '2026-02-01', '2026-02-28', 'Q1', 'Closed'),
  (2026, 3, 'FY2026-P03', 'P03 2026', 'Regular', '2026-03-01', '2026-03-31', 'Q1', 'Closed'),
  (2026, 4, 'FY2026-P04', 'P04 2026', 'Regular', '2026-04-01', '2026-04-30', 'Q2', 'Closed'),
  (2026, 5, 'FY2026-P05', 'P05 2026', 'Regular', '2026-05-01', '2026-05-31', 'Q2', 'Open'),
  (2026, 6, 'FY2026-P06', 'P06 2026', 'Regular', '2026-06-01', '2026-06-30', 'Q2', 'Open'),
  (2026, 7, 'FY2026-P07', 'P07 2026', 'Regular', '2026-07-01', '2026-07-31', 'Q3', 'Open'),
  (2026, 8, 'FY2026-P08', 'P08 2026', 'Regular', '2026-08-01', '2026-08-31', 'Q3', 'Open'),
  (2026, 9, 'FY2026-P09', 'P09 2026', 'Regular', '2026-09-01', '2026-09-30', 'Q3', 'Open'),
  (2026, 10, 'FY2026-P10', 'P10 2026', 'Regular', '2026-10-01', '2026-10-31', 'Q4', 'Open'),
  (2026, 11, 'FY2026-P11', 'P11 2026', 'Regular', '2026-11-01', '2026-11-30', 'Q4', 'Open'),
  (2026, 12, 'FY2026-P12', 'P12 2026', 'Regular', '2026-12-01', '2026-12-31', 'Q4', 'Open');

INSERT INTO epm_staging.budget_cycles
  (name, scenario_id, fiscal_year, rate_set, as_of_date, horizon_periods)
VALUES
  ('ZZ-ACG-R1', 'ZZ_FC_ACG', 2026, 'ZZBUD', '2026-03-31', 3),
  ('ZZ-ACG-B', 'ZZ_PLAN_ACG', 2026, 'ZZBUD', DEFAULT, 0);
ALTER TABLE epm_gold.gold_consolidated_budget_tb ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_consolidated_budget_tb ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_consolidated_budget_tb
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name,
   dim_cost_center, dim_department, scenario_id, cycle, layer, local_amount,
   accounting_currency, reporting_currency, ownership_pct, consolidation_method,
   closing_rate, average_rate, translation_rate, translated_amount, group_amount, nci_amount, rate_set)
VALUES
  ('ZZG', 'ZZE1', 2026, 4, 'ZZ4000', 'ZZ revenue', '', '', 'ZZ_FC_ACG', 'ZZ-ACG-R1', 'base', -45, 'USD', 'USD', 1, 'full', 1, 1, 1, -45, -45, 0, 'ZZBUD'),
  ('ZZG', 'ZZE1', 2026, 4, 'ZZ4000', 'ZZ revenue', '', '', 'ZZ_FC_ACG', 'ZZ-ACG-R1', 'challenge', -5, 'USD', 'USD', 1, 'full', 1, 1, 1, -5, -5, 0, 'ZZBUD'),
  ('ZZG', 'ZZE1', 2026, 4, 'ZZ5000', 'ZZ cost', '', '', 'ZZ_FC_ACG', 'ZZ-ACG-R1', 'base', 20, 'USD', 'USD', 1, 'full', 1, 1, 1, 20, 20, 0, 'ZZBUD'),
  ('ZZG', 'ZZE2', 2026, 4, 'ZZ4000', 'ZZ revenue', '', '', 'ZZ_FC_ACG', 'ZZ-ACG-R1', 'base', -100, 'EUR', 'USD', 1, 'full', 1.1, 1.1, 1.1, -110, -110, 0, 'ZZBUD'),
  ('ZZG', 'ZZE1', 2026, 3, 'ZZ4000', 'ZZ revenue', '', '', 'ZZ_FC_ACG', 'ZZ-ACG-R1', 'base', -30, 'USD', 'USD', 1, 'full', 1, 1, 1, -30, -30, 0, 'ZZBUD'),
  ('ZZG', 'ZZE1', 2026, 5, 'ZZ4000', 'ZZ revenue', '', '', 'ZZ_FC_ACG', 'ZZ-ACG-R1', 'base', -60, 'USD', 'USD', 1, 'full', 1, 1, 1, -60, -60, 0, 'ZZBUD'),
  ('ZZG2', 'ZZE1', 2026, 4, 'ZZ4000', 'ZZ revenue', '', '', 'ZZ_FC_ACG', 'ZZ-ACG-R1', 'base', -50, 'USD', 'USD', 0.5, 'proportional', 1, 1, 1, -50, -25, 0, 'ZZBUD'),
  ('ZZG', 'ZZE1', 2026, 4, 'ZZ4000', 'ZZ revenue', '', '', 'ZZ_PLAN_ACG', 'ZZ-ACG-B', 'base', -999, 'USD', 'USD', 1, 'full', 1, 1, 1, -999, -999, 0, 'ZZBUD');
ALTER TABLE epm_gold.gold_consolidated_trial_balance ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_consolidated_trial_balance ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_consolidated_trial_balance
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name,
   is_balance_sheet, is_pnl, is_equity, dim_cost_center, dim_department, local_amount,
   accounting_currency, reporting_currency, ownership_pct, consolidation_method, closing_rate, average_rate,
   historical_equity_rate, translation_rate, translated_amount, group_amount, nci_amount, partner_data_area_id)
VALUES
  ('ZZG', 'ZZE1', 2026, 4, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, '', '', -40, 'USD', 'USD', 1, 'full', 1, 1, NULL, 1, -40, -40, 0, ''),
  ('ZZG', 'ZZE1', 2026, 4, 'ZZ6000', 'ZZ other cost', 'Expense', 0, 1, 0, '', '', 8, 'USD', 'USD', 1, 'full', 1, 1, NULL, 1, 8, 8, 0, ''),
  ('ZZG', 'ZZE2', 2026, 4, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, '', '', -100, 'EUR', 'USD', 1, 'full', 1.2, 1.2, NULL, 1.2, -120, -120, 0, ''),
  ('ZZG', 'ZZE3', 2026, 4, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, '', '', -7, 'USD', 'USD', 1, 'full', 1, 1, NULL, 1, -7, -7, 0, ''),
  ('ZZG', 'ZZE1', 2026, 5, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, '', '', -61, 'USD', 'USD', 1, 'full', 1, 1, NULL, 1, -61, -61, 0, ''),
  ('ZZG2', 'ZZE1', 2026, 4, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, 0, '', '', -40, 'USD', 'USD', 0.5, 'proportional', 1, 1, NULL, 1, -40, -20, 0, '');
