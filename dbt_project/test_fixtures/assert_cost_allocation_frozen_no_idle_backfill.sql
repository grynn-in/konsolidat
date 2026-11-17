-- gate: build gold_cost_allocation_frozen assert_cost_allocation_frozen_no_idle_backfill
-- gate: expect gold_cost_allocation_frozen built
-- gate: expect assert_cost_allocation_frozen_no_idle_backfill pass
-- konsol#269 RF8: the frozen table is already in the new shape (hop_kind filled, no blank
-- row), so the build must not run the backfill UPDATE (a mutation on every build).
-- ZZRK: Freeze at Approval, already frozen; nothing to insert.
-- tables epm_gold.gold_scenario_trial_balance, epm_gold.gold_cost_allocation_frozen
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZRK','ZZRS1','Direct','dim_cost_center','Sender''s Own Accounts','','Freeze at Approval','ZZE1','ZZSC',2026,1);
INSERT INTO epm_staging.cost_allocation_run_accounts (parent, idx, main_account, declared_account) VALUES
('ZZRK',1,'ZZ6000','');
INSERT INTO epm_staging.cost_allocation_coefficients (run, origin_member, step, sender_member, receiver_member, driver, hop_kind, pool_coefficient, coefficient) VALUES
('ZZRK','ZZIT',1,'ZZIT','ZZP1','ZZHC','own',1,1);
INSERT INTO epm_gold.gold_scenario_trial_balance (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, amount) VALUES
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZIT',1000);
INSERT INTO epm_gold.gold_cost_allocation_frozen (run, rule_set, method, scenario_id, data_area_id, main_account, pool_account, allocation_dimension, member, line_type, hop_kind, origin_member, sender_member, receiver_member, driver, fiscal_year, fiscal_period, step, coefficient, origin_amount, amount, frozen_at) VALUES
('ZZRK','ZZRS1','Direct','ZZSC','ZZE1','ZZ6000','ZZ6000','dim_cost_center','ZZIT','sent','own','ZZIT','ZZIT','ZZP1','ZZHC',2026,1,1,1,1000,-1000,'2026-11-01 10:00:00'),
('ZZRK','ZZRS1','Direct','ZZSC','ZZE1','ZZ6000','ZZ6000','dim_cost_center','ZZP1','received','own','ZZIT','ZZIT','ZZP1','ZZHC',2026,1,1,1,1000,1000,'2026-11-01 10:00:00');
