-- gate: build gold_cost_allocation_frozen gold_cost_allocation assert_cost_allocation_frozen_consistent assert_cost_allocation_conserved assert_cost_allocation_coefficients_close
-- gate: expect gold_cost_allocation_frozen built
-- gate: expect gold_cost_allocation built
-- gate: expect assert_cost_allocation_frozen_consistent pass
-- gate: expect assert_cost_allocation_conserved pass
-- gate: expect assert_cost_allocation_coefficients_close pass
-- konsol#269 W5 clean fixture, one build over a table that already holds frozen rows.
-- Cost centre ZZIT sends its ZZ6000 pool to ZZP1 in full (coefficient 1) in every run:
--   ZZRL  Follow Latest Data, ZZE1 P1, TB 800   -> live lines of 800, frozen_at NULL.
--   ZZRF  Freeze at Approval, ZZE3 P2, TB now 1500; frozen earlier (frozen_at 2026-11-01)
--         at 1000 and already in the frozen table -> its lines stay at 1000, once.
--   ZZRN  Freeze at Approval, ZZE2 P1, TB 600, no frozen rows yet -> frozen now, 600.
--   ZZRG  frozen rows in the table, no run in staging (cancelled) -> removed.
-- tables epm_gold.gold_scenario_trial_balance, epm_gold.gold_cost_allocation_frozen
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZRL','ZZRS1','Direct','dim_cost_center','Sender''s Own Accounts','','Follow Latest Data','ZZE1','ZZSC',2026,1),
('ZZRF','ZZRS1','Direct','dim_cost_center','Sender''s Own Accounts','','Freeze at Approval','ZZE3','ZZSC',2026,2),
('ZZRN','ZZRS1','Direct','dim_cost_center','Sender''s Own Accounts','','Freeze at Approval','ZZE2','ZZSC',2026,1);
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
