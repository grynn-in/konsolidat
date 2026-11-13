-- gate: expect assert_cost_allocation_frozen_drift flag 1
-- konsol#269 W6 (T6) must-flag fixture: two frozen runs, one drifted (warn severity).
-- ZZRP: frozen at 1000, TB still 1000 -> not flagged.
-- ZZRD: frozen at 1000, TB corrected to 1500 after freezing -> flagged once.
-- tables epm_gold.gold_scenario_trial_balance, epm_gold.gold_cost_allocation_frozen
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZRP','ZZRS1','Direct','dim_cost_center','Same Account','','Freeze at Approval','ZZE1','ZZSC',2026,1),
('ZZRD','ZZRS1','Direct','dim_cost_center','Same Account','','Freeze at Approval','ZZE2','ZZSC',2026,1);
INSERT INTO epm_staging.cost_allocation_run_accounts (parent, idx, main_account, declared_account) VALUES
('ZZRP',1,'ZZ6000',''),('ZZRD',1,'ZZ6000','');
INSERT INTO epm_gold.gold_scenario_trial_balance (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, amount) VALUES
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZIT',1000),
('ZZSC','ZZE2',2026,1,'ZZ6000','ZZIT',1500);
INSERT INTO epm_gold.gold_cost_allocation_frozen (run, rule_set, method, scenario_id, data_area_id, main_account, allocation_dimension, member, line_type, origin_member, sender_member, receiver_member, driver, fiscal_year, fiscal_period, step, coefficient, origin_amount, amount, frozen_at) VALUES
('ZZRP','ZZRS1','Direct','ZZSC','ZZE1','ZZ6000','dim_cost_center','ZZIT','sent','ZZIT','ZZIT','ZZP1','ZZHC',2026,1,1,1,1000,-1000,'2026-11-01 10:00:00'),
('ZZRP','ZZRS1','Direct','ZZSC','ZZE1','ZZ6000','dim_cost_center','ZZP1','received','ZZIT','ZZIT','ZZP1','ZZHC',2026,1,1,1,1000,1000,'2026-11-01 10:00:00'),
('ZZRD','ZZRS1','Direct','ZZSC','ZZE2','ZZ6000','dim_cost_center','ZZIT','sent','ZZIT','ZZIT','ZZP1','ZZHC',2026,1,1,1,1000,-1000,'2026-11-01 10:00:00'),
('ZZRD','ZZRS1','Direct','ZZSC','ZZE2','ZZ6000','dim_cost_center','ZZP1','received','ZZIT','ZZIT','ZZP1','ZZHC',2026,1,1,1,1000,1000,'2026-11-01 10:00:00');
