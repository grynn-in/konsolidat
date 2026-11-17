-- gate: build gold_cost_allocation_frozen gold_cost_allocation assert_cost_allocation_balanced_per_account assert_cost_allocation_conserved assert_cost_allocation_coefficients_close assert_cost_allocation_frozen_consistent assert_cost_allocation_frozen_drift
-- gate: expect gold_cost_allocation_frozen built
-- gate: expect gold_cost_allocation built
-- gate: expect assert_cost_allocation_balanced_per_account pass
-- gate: expect assert_cost_allocation_conserved pass
-- gate: expect assert_cost_allocation_coefficients_close pass
-- gate: expect assert_cost_allocation_frozen_consistent pass
-- gate: expect assert_cost_allocation_frozen_drift pass
-- konsol#269 RF2: a frozen table built by phase 1 has NO hop_kind column. The next build must
-- add it and backfill it (sender = origin -> 'own', else 'pass'; only Direct and Step-Down
-- existed then), not fail with UNKNOWN_IDENTIFIER hop_kind / on_schema_change='fail'.
-- The gate clones the frozen table from the live warehouse, which has the NEW shape, so this
-- fixture DROPs the scratch copy and CREATEs it as phase 1 made it, then seeds old rows.
-- ZZRD: Step-Down, Sender's Own Accounts, Freeze at Approval, ZZE1 P1. TB ZZ6000: ZZIT 1000,
-- ZZHR 400 (the frozen pools: no drift). ZZIT -> ZZHR .2, ZZP1 .8; ZZHR passes on its .2 of
-- ZZIT to ZZP1 (.2 of 1000 = 200); ZZHR's own 400 -> ZZP1. With hop_kind left '' the pools
-- are not found and the per-account test fails; backfilled, every test passes.
-- tables epm_gold.gold_scenario_trial_balance, epm_gold.gold_cost_allocation_frozen
DROP TABLE epm_gold.gold_cost_allocation_frozen;
CREATE TABLE epm_gold.gold_cost_allocation_frozen (
    run String, rule_set String, method String, scenario_id String, data_area_id String,
    main_account String, pool_account String, allocation_dimension String, member String,
    line_type String, origin_member String, sender_member String, receiver_member String,
    driver String, fiscal_year UInt16, fiscal_period UInt8, step UInt16,
    coefficient Decimal(38, 12), origin_amount Decimal(38, 4), amount Decimal(38, 16),
    frozen_at Nullable(DateTime)
) ENGINE = MergeTree() ORDER BY (run, origin_member, step, sender_member, receiver_member, line_type);
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZRD','ZZRS1','Step-Down','dim_cost_center','Sender''s Own Accounts','','Freeze at Approval','ZZE1','ZZSC',2026,1);
INSERT INTO epm_staging.cost_allocation_run_accounts (parent, idx, main_account, declared_account) VALUES
('ZZRD',1,'ZZ6000','');
INSERT INTO epm_staging.cost_allocation_coefficients (run, origin_member, step, sender_member, receiver_member, driver, hop_kind, pool_coefficient, coefficient) VALUES
('ZZRD','ZZIT',1,'ZZIT','ZZHR','ZZHC','own',1,0.2),
('ZZRD','ZZIT',1,'ZZIT','ZZP1','ZZHC','own',1,0.8),
('ZZRD','ZZIT',2,'ZZHR','ZZP1','ZZHC','pass',0.2,0.2),
('ZZRD','ZZHR',2,'ZZHR','ZZP1','ZZHC','own',1,1);
INSERT INTO epm_gold.gold_scenario_trial_balance (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, amount) VALUES
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZIT',1000),
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZHR',400);
INSERT INTO epm_gold.gold_cost_allocation_frozen (run, rule_set, method, scenario_id, data_area_id, main_account, pool_account, allocation_dimension, member, line_type, origin_member, sender_member, receiver_member, driver, fiscal_year, fiscal_period, step, coefficient, origin_amount, amount, frozen_at) VALUES
('ZZRD','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6000','ZZ6000','dim_cost_center','ZZIT','sent','ZZIT','ZZIT','ZZHR','ZZHC',2026,1,1,0.2,1000,-200,'2026-11-01 10:00:00'),
('ZZRD','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6000','ZZ6000','dim_cost_center','ZZHR','received','ZZIT','ZZIT','ZZHR','ZZHC',2026,1,1,0.2,1000,200,'2026-11-01 10:00:00'),
('ZZRD','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6000','ZZ6000','dim_cost_center','ZZIT','sent','ZZIT','ZZIT','ZZP1','ZZHC',2026,1,1,0.8,1000,-800,'2026-11-01 10:00:00'),
('ZZRD','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6000','ZZ6000','dim_cost_center','ZZP1','received','ZZIT','ZZIT','ZZP1','ZZHC',2026,1,1,0.8,1000,800,'2026-11-01 10:00:00'),
('ZZRD','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6000','ZZ6000','dim_cost_center','ZZHR','sent','ZZIT','ZZHR','ZZP1','ZZHC',2026,1,2,0.2,1000,-200,'2026-11-01 10:00:00'),
('ZZRD','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6000','ZZ6000','dim_cost_center','ZZP1','received','ZZIT','ZZHR','ZZP1','ZZHC',2026,1,2,0.2,1000,200,'2026-11-01 10:00:00'),
('ZZRD','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6000','ZZ6000','dim_cost_center','ZZHR','sent','ZZHR','ZZHR','ZZP1','ZZHC',2026,1,2,1,400,-400,'2026-11-01 10:00:00'),
('ZZRD','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6000','ZZ6000','dim_cost_center','ZZP1','received','ZZHR','ZZHR','ZZP1','ZZHC',2026,1,2,1,400,400,'2026-11-01 10:00:00');
