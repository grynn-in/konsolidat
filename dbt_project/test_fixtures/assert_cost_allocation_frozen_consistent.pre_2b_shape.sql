-- gate: build gold_cost_allocation_frozen gold_cost_allocation assert_cost_allocation_balanced_per_account assert_cost_allocation_conserved assert_cost_allocation_coefficients_close assert_cost_allocation_frozen_consistent assert_cost_allocation_frozen_drift assert_cost_allocation_hop_kind_valid assert_cost_allocation_basis_valid
-- gate: expect gold_cost_allocation_frozen built
-- gate: expect gold_cost_allocation built
-- gate: expect assert_cost_allocation_balanced_per_account pass
-- gate: expect assert_cost_allocation_conserved pass
-- gate: expect assert_cost_allocation_coefficients_close pass
-- gate: expect assert_cost_allocation_frozen_consistent pass
-- gate: expect assert_cost_allocation_frozen_drift pass
-- gate: expect assert_cost_allocation_hop_kind_valid pass
-- gate: expect assert_cost_allocation_basis_valid pass
-- konsol#269 2b-2 W5: a frozen table built by phase 2a has hop_kind but NO basis column. The next
-- build must add it with DEFAULT 'Share of Pool' (a pre_hook ALTER, no mutation: every row frozen
-- before 2b-2 was a share-of-pool row) and not fail with on_schema_change='fail'. The gate clones the
-- frozen table from the live warehouse, which has the NEW shape, so this fixture DROPs the scratch
-- copy and CREATEs it as phase 2a made it, then seeds 2a rows.
-- ZZRD (2a rows): Step-Down, Sender's Own Accounts, Freeze at Approval, ZZE1 P1, frozen at TB ZZ6000
--   ZZIT 1000, ZZHR 400 (no drift). ZZIT -> ZZHR .2, ZZP1 .8; ZZHR passes its 200 on to ZZP1; ZZHR's own
--   400 -> ZZP1. After the build these rows read basis 'Share of Pool' (the default), so
--   assert_cost_allocation_basis_valid passes and the drift and balance tests find their pools.
-- ZZRN (new): Step-Down, Declared Allocation Account ZZ6999, Freeze at Approval, ZZE2 P1, frozen by
--   this build: ZZIT charges 50 per ticket (ZZHR 5, ZZSA 8, ZZOP 6), ZZHR splits its 400 5/8 : 3/8. Its
--   rows land in the upgraded table with basis 'Declared Rate' (origin ZZIT) and 'Share of Pool' (ZZHR)
--   beside the defaulted 2a rows: ZZ6999 ZZSA 806.25, ZZOP 543.75, ZZIT -950, ZZHR 0; ZZ6000 ZZHR -400.
-- tables epm_gold.gold_scenario_trial_balance, epm_gold.gold_cost_allocation_frozen
DROP TABLE epm_gold.gold_cost_allocation_frozen;
CREATE TABLE epm_gold.gold_cost_allocation_frozen (
    run String, rule_set String, method String, scenario_id String, data_area_id String,
    main_account String, pool_account String, allocation_dimension String, member String,
    line_type String, hop_kind String, origin_member String, sender_member String, receiver_member String,
    driver String, fiscal_year UInt16, fiscal_period UInt8, step UInt16,
    coefficient Decimal(38, 12), origin_amount Decimal(38, 4), amount Decimal(38, 16),
    frozen_at Nullable(DateTime)
) ENGINE = MergeTree() ORDER BY (run, origin_member, step, sender_member, receiver_member, line_type);
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZRD','ZZRS1','Step-Down','dim_cost_center','Sender''s Own Accounts','','Freeze at Approval','ZZE1','ZZSC',2026,1),
('ZZRN','ZZRS2','Step-Down','dim_cost_center','Declared Allocation Account','ZZ6999','Freeze at Approval','ZZE2','ZZSC',2026,1);
INSERT INTO epm_staging.cost_allocation_run_accounts (parent, idx, main_account, declared_account) VALUES
('ZZRD',1,'ZZ6000',''),('ZZRN',1,'ZZ6000','');
INSERT INTO epm_staging.cost_allocation_run_weights (parent, idx, step, sender_member, receiver_member, driver, statistic, value_period, carried_forward, driver_value, source, effective_from, basis, rate, rate_from) VALUES
('ZZRN',1,1,'ZZIT','ZZHR','ZZ Tickets','ZZ Tickets',1,0,5,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRN',2,1,'ZZIT','ZZSA','ZZ Tickets','ZZ Tickets',1,0,8,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRN',3,1,'ZZIT','ZZOP','ZZ Tickets','ZZ Tickets',1,0,6,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRN',4,2,'ZZHR','ZZSA','ZZ Headcount','ZZ Headcount',1,0,5,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01'),
('ZZRN',5,2,'ZZHR','ZZOP','ZZ Headcount','ZZ Headcount',1,0,3,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01');
INSERT INTO epm_staging.cost_allocation_coefficients (run, origin_member, step, sender_member, receiver_member, driver, hop_kind, pool_coefficient, coefficient) VALUES
('ZZRD','ZZIT',1,'ZZIT','ZZHR','ZZHC','own',1,0.2),
('ZZRD','ZZIT',1,'ZZIT','ZZP1','ZZHC','own',1,0.8),
('ZZRD','ZZIT',2,'ZZHR','ZZP1','ZZHC','pass',0.2,0.2),
('ZZRD','ZZHR',2,'ZZHR','ZZP1','ZZHC','own',1,1),
('ZZRN','ZZIT',1,'ZZIT','ZZHR','ZZ Tickets','own',19.000000000000,5.000000000000),
('ZZRN','ZZIT',1,'ZZIT','ZZSA','ZZ Tickets','own',19.000000000000,8.000000000000),
('ZZRN','ZZIT',1,'ZZIT','ZZOP','ZZ Tickets','own',19.000000000000,6.000000000000),
('ZZRN','ZZIT',2,'ZZHR','ZZSA','ZZ Headcount','pass',5.000000000000,3.125000000000),
('ZZRN','ZZIT',2,'ZZHR','ZZOP','ZZ Headcount','pass',5.000000000000,1.875000000000),
('ZZRN','ZZHR',2,'ZZHR','ZZSA','ZZ Headcount','own',1.000000000000,0.625000000000),
('ZZRN','ZZHR',2,'ZZHR','ZZOP','ZZ Headcount','own',1.000000000000,0.375000000000);
INSERT INTO epm_gold.gold_scenario_trial_balance (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, amount) VALUES
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZIT',1000),
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZHR',400),
('ZZSC','ZZE2',2026,1,'ZZ6000','ZZIT',1000),
('ZZSC','ZZE2',2026,1,'ZZ6000','ZZHR',400);
INSERT INTO epm_gold.gold_cost_allocation_frozen (run, rule_set, method, scenario_id, data_area_id, main_account, pool_account, allocation_dimension, member, line_type, hop_kind, origin_member, sender_member, receiver_member, driver, fiscal_year, fiscal_period, step, coefficient, origin_amount, amount, frozen_at) VALUES
('ZZRD','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6000','ZZ6000','dim_cost_center','ZZIT','sent','own','ZZIT','ZZIT','ZZHR','ZZHC',2026,1,1,0.2,1000,-200,'2026-11-01 10:00:00'),
('ZZRD','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6000','ZZ6000','dim_cost_center','ZZHR','received','own','ZZIT','ZZIT','ZZHR','ZZHC',2026,1,1,0.2,1000,200,'2026-11-01 10:00:00'),
('ZZRD','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6000','ZZ6000','dim_cost_center','ZZIT','sent','own','ZZIT','ZZIT','ZZP1','ZZHC',2026,1,1,0.8,1000,-800,'2026-11-01 10:00:00'),
('ZZRD','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6000','ZZ6000','dim_cost_center','ZZP1','received','own','ZZIT','ZZIT','ZZP1','ZZHC',2026,1,1,0.8,1000,800,'2026-11-01 10:00:00'),
('ZZRD','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6000','ZZ6000','dim_cost_center','ZZHR','sent','pass','ZZIT','ZZHR','ZZP1','ZZHC',2026,1,2,0.2,1000,-200,'2026-11-01 10:00:00'),
('ZZRD','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6000','ZZ6000','dim_cost_center','ZZP1','received','pass','ZZIT','ZZHR','ZZP1','ZZHC',2026,1,2,0.2,1000,200,'2026-11-01 10:00:00'),
('ZZRD','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6000','ZZ6000','dim_cost_center','ZZHR','sent','own','ZZHR','ZZHR','ZZP1','ZZHC',2026,1,2,1,400,-400,'2026-11-01 10:00:00'),
('ZZRD','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6000','ZZ6000','dim_cost_center','ZZP1','received','own','ZZHR','ZZHR','ZZP1','ZZHC',2026,1,2,1,400,400,'2026-11-01 10:00:00');
