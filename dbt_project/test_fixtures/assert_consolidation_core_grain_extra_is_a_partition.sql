-- assert_consolidation_core_grain_extra_is_a_partition (konsol#348 S4, W3): must PASS.
-- gate: build gold_ownership_exits assert_consolidation_core_grain_extra_is_a_partition
-- The core's inputs only, seeded directly. Build mode, so that gold_ownership_exits is built (#335, X23):
-- the core reads the exit events from that table (spine_stints), and test mode would clone it empty from
-- epm_gold, or ERROR where the warehouse has no such table. It builds from the empty ownership sources, so
-- it holds no exit, as this case needs; no other model is built. Two EUR entities in a
-- USD group, 100% owned, the same case as assert_year_end_close_carries_no_cta so every window
-- in the core has work to do: ZZ1000 cash is a closing-rate balance sheet key retranslated at
-- every rate change (key_before / key_all); ZZE1's ZZ1100 receivable and ZZ2000 payable move in
-- P11 only, so they get filler rows in P12 and FY2026 P1 (filler_candidates / fillers, keyed on
-- the layer too); ZZ4000 revenue is reversed by the year-end close in P13 (key_year_before);
-- ZZ3100 retained earnings takes the close lump (close_period); ZZE1 has a historical tranche
-- for ZZ3100 (the ASOF join). The test duplicates these rows under two layers and expects each
-- layer to equal the whole; a window or join that lost the layer doubles a balance here.
-- Signed zeros (W3 review): every negative row of these 100%-owned entities has nci_amount =
-- translated x 0.0 = -0.0 (revenue, payables, the retained-earnings close), and ZZE1's ZZ2000
-- movement in P13 carries a retranslation of cum_local(-30) x (1.20 - 1.20) = -0.0; the test's
-- normaliser must group those with +0.0, or they would flag.
-- Calendar: FY2025 P11, P12 (Regular), P13 (Closing, translated at P12's rates), FY2026 P1.
-- Governed EUR->USD: 2025 P11 1.05/1.00; 2025 P12 1.20/1.10; 2026 P1 1.25/1.22 (closing/average).
INSERT INTO epm_silver.silver_main_accounts
  (main_account_id, account_name, account_type, account_type_name, is_pnl, is_balance_sheet, is_equity, fx_method, is_posting, is_retained_earnings, uses_historical_rate)
VALUES
  ('ZZ1000', 'ZZ cash', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ1100', 'ZZ receivables', 'Asset', 'Asset', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ2000', 'ZZ payables', 'Liability', 'Liability', 0, 1, 0, 'closing', 1, 0, 0),
  ('ZZ3100', 'ZZ retained earnings', 'Equity', 'Equity', 0, 1, 1, 'historical', 1, 1, 1),
  ('ZZ4000', 'ZZ revenue', 'Revenue', 'Revenue', 1, 0, 0, 'average', 1, 0, 0);
INSERT INTO epm_silver.silver_entity_currencies
  (data_area_id, accounting_currency)
VALUES
  ('ZZE1', 'EUR'),
  ('ZZE2', 'EUR');
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency)
VALUES
  ('ZZG', '', 'ZZ Group', 'USD'),
  ('ZZG', 'ZZE1', 'ZZ Entity 1', 'USD'),
  ('ZZG', 'ZZE2', 'ZZ Entity 2', 'USD');
INSERT INTO epm_gold.gold_entity_ownership
  (consolidation_group, data_area_id, fiscal_year, fiscal_period, period_date, chain_depth, owner_group, has_complete_chain, outside_ownership_window, effective_ownership_pct, direct_ownership_pct, consolidation_method)
VALUES
  ('ZZG', 'ZZE1', 2025, 11, '2025-11-30', 1, 'ZZG', 1, 0, 1.0, 1.0, 'full'),
  ('ZZG', 'ZZE1', 2025, 12, '2025-12-31', 1, 'ZZG', 1, 0, 1.0, 1.0, 'full'),
  ('ZZG', 'ZZE1', 2025, 13, '2025-12-31', 1, 'ZZG', 1, 0, 1.0, 1.0, 'full'),
  ('ZZG', 'ZZE1', 2026, 1, '2026-01-31', 1, 'ZZG', 1, 0, 1.0, 1.0, 'full'),
  ('ZZG', 'ZZE2', 2025, 11, '2025-11-30', 1, 'ZZG', 1, 0, 1.0, 1.0, 'full'),
  ('ZZG', 'ZZE2', 2025, 12, '2025-12-31', 1, 'ZZG', 1, 0, 1.0, 1.0, 'full'),
  ('ZZG', 'ZZE2', 2025, 13, '2025-12-31', 1, 'ZZG', 1, 0, 1.0, 1.0, 'full'),
  ('ZZG', 'ZZE2', 2026, 1, '2026-01-31', 1, 'ZZG', 1, 0, 1.0, 1.0, 'full');
-- The live table may predate to_currency (konsol#374): add it to the scratch clone first.
ALTER TABLE epm_staging.historical_equity_rates ADD COLUMN IF NOT EXISTS to_currency LowCardinality(String);
-- konsol#348 S4-Q7 (a): the one Rate Set flagged Is Actuals. The consolidation reads rates of
-- this set only, and its guard refuses a build with zero or two flagged sets.
INSERT INTO epm_staging.rate_sets
  (rate_set, label, is_actuals)
VALUES
  ('ZZACT', 'ZZ actuals', 1);
ALTER TABLE epm_staging.historical_equity_rates ADD COLUMN IF NOT EXISTS rate_set String;
INSERT INTO epm_staging.historical_equity_rates
  (consolidation_group, data_area_id, main_account, rate_date, historical_rate, to_currency, rate_set)
VALUES
  ('ZZG', 'ZZE1', 'ZZ3100', '2020-01-01', 0.90, 'USD', 'ZZACT');
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2025, 11, 'FY2025-P11', 'Nov 2025', 'Regular', '2025-11-01', '2025-11-30', 'Q4', 'Open'),
  (2025, 12, 'FY2025-P12', 'Dec 2025', 'Regular', '2025-12-01', '2025-12-31', 'Q4', 'Open'),
  (2025, 13, 'FY2025-P13', 'FY2025 closing', 'Closing', '2025-12-31', '2025-12-31', 'Q4', 'Open'),
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open');
-- The live rate tables may predate konsol#348's rate_set: add it to the scratch clones first.
ALTER TABLE epm_staging.group_exchange_rates ADD COLUMN IF NOT EXISTS rate_set String;
INSERT INTO epm_staging.group_exchange_rates
  (to_currency, from_currency, fiscal_year, fiscal_period, rate_type, rate, document, rate_set)
VALUES
  ('USD', 'EUR', 2025, 11, 'Closing', 1.05, 'ZZ-GER-2025-11', 'ZZACT'),
  ('USD', 'EUR', 2025, 11, 'Average', 1.00, 'ZZ-GER-2025-11', 'ZZACT'),
  ('USD', 'EUR', 2025, 12, 'Closing', 1.20, 'ZZ-GER-2025-12', 'ZZACT'),
  ('USD', 'EUR', 2025, 12, 'Average', 1.10, 'ZZ-GER-2025-12', 'ZZACT'),
  ('USD', 'EUR', 2026, 1, 'Closing', 1.25, 'ZZ-GER-2026-01', 'ZZACT'),
  ('USD', 'EUR', 2026, 1, 'Average', 1.22, 'ZZ-GER-2026-01', 'ZZACT');
-- The partner-grained trial balance the core reads, as gold_trial_balance_by_partner builds it
-- (one row per key and period; is_year_end_close marks the close rows in P13).
ALTER TABLE epm_gold.gold_trial_balance_by_partner ADD COLUMN IF NOT EXISTS is_year_end_close UInt8 DEFAULT 0;
INSERT INTO epm_gold.gold_trial_balance_by_partner
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl,
   partner_data_area_id, dim_business_unit, dim_cost_center, dim_department,
   period_credit, period_debit, period_net_amount, transaction_count, is_year_end_close)
VALUES
  ('ZZE1', 2025, 11, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, '', '', '', '', 0, 60, 60, 1, 0),
  ('ZZE1', 2025, 11, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', '', '', '', 60, 0, -60, 1, 0),
  ('ZZE1', 2025, 11, 'ZZ1100', 'ZZ receivables', 'Asset', 1, 0, '', '', '', '', 0, 30, 30, 1, 0),
  ('ZZE1', 2025, 11, 'ZZ2000', 'ZZ payables', 'Liability', 1, 0, '', '', '', '', 30, 0, -30, 1, 0),
  ('ZZE1', 2025, 12, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, '', '', '', '', 0, 40, 40, 1, 0),
  ('ZZE1', 2025, 12, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', '', '', '', 40, 0, -40, 1, 0),
  ('ZZE1', 2025, 13, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', '', '', '', 0, 100, 100, 1, 1),
  ('ZZE1', 2025, 13, 'ZZ3100', 'ZZ retained earnings', 'Equity', 1, 0, '', '', '', '', 100, 0, -100, 1, 1),
  ('ZZE1', 2025, 13, 'ZZ2000', 'ZZ payables', 'Liability', 1, 0, '', '', '', '', 5, 0, -5, 1, 0),
  ('ZZE1', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, '', '', '', '', 0, 50, 50, 1, 0),
  ('ZZE1', 2026, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', '', '', '', 50, 0, -50, 1, 0),
  ('ZZE2', 2025, 12, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, '', '', '', '', 0, 100, 100, 1, 0),
  ('ZZE2', 2025, 12, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', '', '', '', 100, 0, -100, 1, 0),
  ('ZZE2', 2025, 13, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', '', '', '', 0, 100, 100, 1, 1),
  ('ZZE2', 2025, 13, 'ZZ3100', 'ZZ retained earnings', 'Equity', 1, 0, '', '', '', '', 100, 0, -100, 1, 1),
  ('ZZE2', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, '', '', '', '', 0, 50, 50, 1, 0),
  ('ZZE2', 2026, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', '', '', '', 50, 0, -50, 1, 0);
