-- gate: expect assert_cost_allocation_amounts flag 3
-- konsol#269 W5b must-flag fixture, seeded gold_cost_allocation read as it stands:
--   ZZRL Follow Latest, TB 800 but published 500 -> stale (1).
--   ZZRX Follow Latest line carrying frozen_at -> stamp violation (1).
--   ZZRY Freeze at Approval line with frozen_at NULL -> stamp violation (1).
-- tables epm_gold.gold_scenario_trial_balance, epm_gold.gold_cost_allocation
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZRL','ZZRS1','Direct','dim_cost_center','Same Account','','Follow Latest Data','ZZE1','ZZSC',2026,1),
('ZZRX','ZZRS1','Direct','dim_cost_center','Same Account','','Follow Latest Data','ZZE2','ZZSC',2026,1),
('ZZRY','ZZRS1','Direct','dim_cost_center','Same Account','','Freeze at Approval','ZZE3','ZZSC',2026,1);
INSERT INTO epm_staging.cost_allocation_run_accounts (parent, idx, main_account, declared_account) VALUES
('ZZRL',1,'ZZ6000',''),('ZZRX',1,'ZZ6000',''),('ZZRY',1,'ZZ6000','');
INSERT INTO epm_gold.gold_scenario_trial_balance (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, amount) VALUES
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZIT',800),
('ZZSC','ZZE2',2026,1,'ZZ6000','ZZIT',600),
('ZZSC','ZZE3',2026,1,'ZZ6000','ZZIT',900);
INSERT INTO epm_gold.gold_cost_allocation (run, rule_set, method, scenario_id, data_area_id, main_account, allocation_dimension, member, line_type, origin_member, sender_member, receiver_member, driver, fiscal_year, fiscal_period, step, coefficient, origin_amount, amount, frozen_at) VALUES
('ZZRL','ZZRS1','Direct','ZZSC','ZZE1','ZZ6000','dim_cost_center','ZZIT','sent','ZZIT','ZZIT','ZZP1','ZZHC',2026,1,1,1,500,-500,NULL),
('ZZRX','ZZRS1','Direct','ZZSC','ZZE2','ZZ6000','dim_cost_center','ZZIT','sent','ZZIT','ZZIT','ZZP1','ZZHC',2026,1,1,1,600,-600,'2026-11-01 10:00:00'),
('ZZRY','ZZRS1','Direct','ZZSC','ZZE3','ZZ6000','dim_cost_center','ZZIT','sent','ZZIT','ZZIT','ZZP1','ZZHC',2026,1,1,1,900,-900,NULL);
