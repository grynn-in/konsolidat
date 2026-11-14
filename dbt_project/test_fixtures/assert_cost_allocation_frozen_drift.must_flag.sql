-- gate: expect assert_cost_allocation_frozen_drift flag 3
-- konsol#269 W6 (T6) must-flag fixture: two frozen runs, one drifted (warn severity).
-- ZZRP: frozen at 1000, TB still 1000 -> not flagged.
-- ZZRD: frozen at 1000, TB corrected to 1500 after freezing -> flagged once.
-- ZZRA: frozen at 1000 for origin ZZIT (unchanged); origin ZZNW has coefficients and got TB data
--   (400) after the freeze, so it has no frozen lines -> flagged once (M3).
-- ZZRB: frozen at 700 for origin ZZIT; the origin's TB data was removed afterwards -> flagged once.
-- tables epm_gold.gold_scenario_trial_balance, epm_gold.gold_cost_allocation_frozen
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZRP','ZZRS1','Direct','dim_cost_center','Same Account','','Freeze at Approval','ZZE1','ZZSC',2026,1),
('ZZRD','ZZRS1','Direct','dim_cost_center','Same Account','','Freeze at Approval','ZZE2','ZZSC',2026,1),
('ZZRA','ZZRS1','Direct','dim_cost_center','Same Account','','Freeze at Approval','ZZE3','ZZSC',2026,1),
('ZZRB','ZZRS1','Direct','dim_cost_center','Same Account','','Freeze at Approval','ZZE4','ZZSC',2026,1);
INSERT INTO epm_staging.cost_allocation_run_accounts (parent, idx, main_account, declared_account) VALUES
('ZZRP',1,'ZZ6000',''),('ZZRD',1,'ZZ6000',''),('ZZRA',1,'ZZ6000',''),('ZZRB',1,'ZZ6000','');
INSERT INTO epm_staging.cost_allocation_coefficients (run, origin_member, step, sender_member, receiver_member, driver, pool_coefficient, coefficient) VALUES
('ZZRP','ZZIT',1,'ZZIT','ZZP1','ZZHC',1,1),
('ZZRD','ZZIT',1,'ZZIT','ZZP1','ZZHC',1,1),
('ZZRA','ZZIT',1,'ZZIT','ZZP1','ZZHC',1,1),
('ZZRA','ZZNW',1,'ZZNW','ZZP1','ZZHC',1,1),
('ZZRB','ZZIT',1,'ZZIT','ZZP1','ZZHC',1,1);
INSERT INTO epm_gold.gold_scenario_trial_balance (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, amount) VALUES
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZIT',1000),
('ZZSC','ZZE2',2026,1,'ZZ6000','ZZIT',1500),
('ZZSC','ZZE3',2026,1,'ZZ6000','ZZIT',1000),
('ZZSC','ZZE3',2026,1,'ZZ6000','ZZNW',400),
('ZZSC','ZZE4',2026,1,'ZZ6000','ZZOT',55);
INSERT INTO epm_gold.gold_cost_allocation_frozen (run, rule_set, method, scenario_id, data_area_id, main_account, allocation_dimension, member, line_type, origin_member, sender_member, receiver_member, driver, fiscal_year, fiscal_period, step, coefficient, origin_amount, amount, frozen_at) VALUES
('ZZRP','ZZRS1','Direct','ZZSC','ZZE1','ZZ6000','dim_cost_center','ZZIT','sent','ZZIT','ZZIT','ZZP1','ZZHC',2026,1,1,1,1000,-1000,'2026-11-01 10:00:00'),
('ZZRP','ZZRS1','Direct','ZZSC','ZZE1','ZZ6000','dim_cost_center','ZZP1','received','ZZIT','ZZIT','ZZP1','ZZHC',2026,1,1,1,1000,1000,'2026-11-01 10:00:00'),
('ZZRD','ZZRS1','Direct','ZZSC','ZZE2','ZZ6000','dim_cost_center','ZZIT','sent','ZZIT','ZZIT','ZZP1','ZZHC',2026,1,1,1,1000,-1000,'2026-11-01 10:00:00'),
('ZZRD','ZZRS1','Direct','ZZSC','ZZE2','ZZ6000','dim_cost_center','ZZP1','received','ZZIT','ZZIT','ZZP1','ZZHC',2026,1,1,1,1000,1000,'2026-11-01 10:00:00'),
('ZZRA','ZZRS1','Direct','ZZSC','ZZE3','ZZ6000','dim_cost_center','ZZIT','sent','ZZIT','ZZIT','ZZP1','ZZHC',2026,1,1,1,1000,-1000,'2026-11-01 10:00:00'),
('ZZRA','ZZRS1','Direct','ZZSC','ZZE3','ZZ6000','dim_cost_center','ZZP1','received','ZZIT','ZZIT','ZZP1','ZZHC',2026,1,1,1,1000,1000,'2026-11-01 10:00:00'),
('ZZRB','ZZRS1','Direct','ZZSC','ZZE4','ZZ6000','dim_cost_center','ZZIT','sent','ZZIT','ZZIT','ZZP1','ZZHC',2026,1,1,1,700,-700,'2026-11-01 10:00:00'),
('ZZRB','ZZRS1','Direct','ZZSC','ZZE4','ZZ6000','dim_cost_center','ZZP1','received','ZZIT','ZZIT','ZZP1','ZZHC',2026,1,1,1,700,700,'2026-11-01 10:00:00');
