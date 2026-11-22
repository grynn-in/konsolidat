-- assert_consolidation_core_grain_extra_is_a_partition, with an exit and a re-entry (#358 review F4 a): must PASS.
-- gate: build gold_ownership_exits assert_consolidation_core_grain_extra_is_a_partition
-- gate: expect assert_consolidation_core_grain_extra_is_a_partition pass
-- The base fixture's case (two EUR entities, 100% full in USD group ZZG; FY2025 P11, P12, Closing P13, FY2026 P1;
-- Closing EUR->USD 1.05, 1.20, 1.25), with ZZE1 leaving the group and coming back. The ownership sources declare
-- ZZE1 full 2020-01-01..2025-11-30 (a bare end) and again from 2026-01-01, so gold_ownership_exits, built here from
-- them, holds one exit: P = FY2025 P11, first period out F = FY2025 P12. The seeded gold_entity_ownership agrees:
-- no ZZE1 row in P12 or P13, and ZZE1 has no trial balance there. ZZE1's keys are therefore stint 0 in P11 and
-- stint 1 in FY2026 P1 under EACH layer, and ZZE2 (no exit) stays stint 0: both grain_extra layers cross a stint
-- boundary. The test passes exits_relation=ref('gold_ownership_exits') to both core calls, so the reset runs in
-- both, and compares the layered run with the whole.
-- Figures the reset decides, the same under ZZA and ZZB as in the whole: ZZE1 ZZ1000 cash in FY2026 P1 is the
-- stint's first row, so it retranslates nothing (0; without the reset 60 x (1.25 - 1.05) = 12); the P11-only
-- ZZ1100 / ZZ2000 keys get no P1 filler (adjustment 0, dropped; without the reset +-30 x 0.20 = +-6).
-- Why a lost `extra` fails here:
--   - densified_stints joined without the layer (dim_join_on(..., dims=extra) dropped): every row matches the
--     spine row of both layers, so each layered row comes out twice; the multiset diff flags it (net -1).
--   - spine_stints without the layer, the join keeping it: ss.zz_layer does not exist, the test ERRORs and
--     the fixture fails.
--   - the exits branch of spine_stints losing the layer (an exit row written on a blank or wrong zz_layer): it
--     joins no layer's spine row, the layers keep stint 0 and do not reset while the whole does: ZZE1 cash P1
--     reads 12 under each layer against 0 expected, and the ZZ1100 / ZZ2000 P1 fillers appear (net -1 each).
--     Only a fixture with an exit reaches this branch: in the base fixture it joins nothing.
--   Dropping the layer from BOTH spine_stints and its join changes no figure: an exit belongs to (group,
--   entity), each layer's spine row then counts it once more (stint 2, not 1), and the boundary is in the same
--   period, which is all the windows read.
ALTER TABLE epm_staging.consolidation_ancestry ADD COLUMN IF NOT EXISTS path_id String, ADD COLUMN IF NOT EXISTS link_owner_group String, ADD COLUMN IF NOT EXISTS link_owner_data_area_id String;
ALTER TABLE epm_staging.ownership_periods ADD COLUMN IF NOT EXISTS owner_group String, ADD COLUMN IF NOT EXISTS owner_data_area_id String, MODIFY ORDER BY (consolidation_group, data_area_id, effective_date, owner_group, owner_data_area_id);
CREATE TABLE IF NOT EXISTS epm_staging.consolidation_method_declarations (consolidation_group String, data_area_id String, consolidation_method String, effective_date Date, end_date Date DEFAULT '9999-12-31', reason String, updated_at DateTime DEFAULT now()) ENGINE = ReplacingMergeTree(updated_at) ORDER BY (consolidation_group, data_area_id, effective_date);
CREATE TABLE IF NOT EXISTS epm_staging.business_disposals (name String, consolidation_group String, disposed_entity String, disposal_date Date, share_disposed_pct Float64, retained_interest_pct Float64, proceeds_currency String, total_proceeds Float64, ownership_period String) ENGINE = MergeTree ORDER BY name;
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZG', 'ZZE1', 'ZZG', 'ZZE1', 1, 1, 'ZZG/ZZE1', 'ZZG/ZZE1', 'ZZG', ''),
  ('ZZG', 'ZZE2', 'ZZG', 'ZZE2', 1, 1, 'ZZG/ZZE2', 'ZZG/ZZE2', 'ZZG', '');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id)
VALUES
  ('ZZG', 'ZZE1', '2020-01-01', '2025-11-30', 100, 'full', 'ZZG', ''),
  ('ZZG', 'ZZE1', '2026-01-01', '2149-06-06', 100, 'full', 'ZZG', ''),
  ('ZZG', 'ZZE2', '2020-01-01', '2149-06-06', 100, 'full', 'ZZG', '');
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
  ('ZZE1', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, '', '', '', '', 0, 50, 50, 1, 0),
  ('ZZE1', 2026, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', '', '', '', 50, 0, -50, 1, 0),
  ('ZZE2', 2025, 12, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, '', '', '', '', 0, 100, 100, 1, 0),
  ('ZZE2', 2025, 12, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', '', '', '', 100, 0, -100, 1, 0),
  ('ZZE2', 2025, 13, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', '', '', '', 0, 100, 100, 1, 1),
  ('ZZE2', 2025, 13, 'ZZ3100', 'ZZ retained earnings', 'Equity', 1, 0, '', '', '', '', 100, 0, -100, 1, 1),
  ('ZZE2', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, '', '', '', '', 0, 50, 50, 1, 0),
  ('ZZE2', 2026, 1, 'ZZ4000', 'ZZ revenue', 'Revenue', 0, 1, '', '', '', '', 50, 0, -50, 1, 0);
