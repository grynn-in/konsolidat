-- gate: build gold_cost_allocation_frozen gold_cost_allocation assert_cost_allocation_frozen_drift --full-refresh
-- gate: expect gold_cost_allocation_frozen built
-- gate: expect gold_cost_allocation built
-- gate: expect assert_cost_allocation_frozen_drift flag 1
-- konsol#269 W5b must-flag fixture: `dbt build --full-refresh` must NOT re-freeze approved runs.
-- ZZRF (Freeze at Approval) was frozen at 1000 and the TB now says 1500. If the full refresh
-- recomputed it, it would be frozen at 1500 and no run would drift (0 flags: red). With
-- full_refresh=false the frozen 1000 stays, so exactly ZZRF drifts (1 flag).
-- ZZRN (Freeze, no frozen rows yet, TB 600) is frozen now at current data: it does not drift.
-- tables epm_gold.gold_scenario_trial_balance, epm_gold.gold_cost_allocation_frozen
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZRL','ZZRS1','Direct','dim_cost_center','Same Account','','Follow Latest Data','ZZE1','ZZSC',2026,1),
('ZZRF','ZZRS1','Direct','dim_cost_center','Same Account','','Freeze at Approval','ZZE3','ZZSC',2026,2),
('ZZRN','ZZRS1','Direct','dim_cost_center','Same Account','','Freeze at Approval','ZZE2','ZZSC',2026,1);
INSERT INTO epm_staging.cost_allocation_run_accounts (parent, idx, main_account, declared_account) VALUES
('ZZRL',1,'ZZ6000',''),('ZZRF',1,'ZZ6000',''),('ZZRN',1,'ZZ6000','');
INSERT INTO epm_staging.cost_allocation_coefficients (run, origin_member, step, sender_member, receiver_member, driver, pool_coefficient, coefficient) VALUES
('ZZRL','ZZIT',1,'ZZIT','ZZP1','ZZHC',1,1),
('ZZRF','ZZIT',1,'ZZIT','ZZP1','ZZHC',1,1),
('ZZRN','ZZIT',1,'ZZIT','ZZP1','ZZHC',1,1);
INSERT INTO epm_gold.gold_scenario_trial_balance (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, amount) VALUES
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZIT',800),
('ZZSC','ZZE3',2026,2,'ZZ6000','ZZIT',1500),
('ZZSC','ZZE2',2026,1,'ZZ6000','ZZIT',600);
INSERT INTO epm_gold.gold_cost_allocation_frozen (run, rule_set, method, scenario_id, data_area_id, main_account, allocation_dimension, member, line_type, origin_member, sender_member, receiver_member, driver, fiscal_year, fiscal_period, step, coefficient, origin_amount, amount, frozen_at) VALUES
('ZZRF','ZZRS1','Direct','ZZSC','ZZE3','ZZ6000','dim_cost_center','ZZIT','sent','ZZIT','ZZIT','ZZP1','ZZHC',2026,2,1,1,1000,-1000,'2026-11-01 10:00:00'),
('ZZRF','ZZRS1','Direct','ZZSC','ZZE3','ZZ6000','dim_cost_center','ZZP1','received','ZZIT','ZZIT','ZZP1','ZZHC',2026,2,1,1,1000,1000,'2026-11-01 10:00:00'),
('ZZRG','ZZRS1','Direct','ZZSC','ZZE4','ZZ6000','dim_cost_center','ZZIT','sent','ZZIT','ZZIT','ZZP1','ZZHC',2026,3,1,1,300,-300,'2026-11-01 10:00:00'),
('ZZRG','ZZRS1','Direct','ZZSC','ZZE4','ZZ6000','dim_cost_center','ZZP1','received','ZZIT','ZZIT','ZZP1','ZZHC',2026,3,1,1,300,300,'2026-11-01 10:00:00');
