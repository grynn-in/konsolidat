-- gate: build gold_cost_allocation_frozen gold_cost_allocation assert_cost_allocation_balanced_per_account assert_cost_allocation_conserved assert_cost_allocation_coefficients_close assert_cost_allocation_frozen_consistent
-- gate: expect gold_cost_allocation_frozen built
-- gate: expect gold_cost_allocation built
-- gate: expect assert_cost_allocation_balanced_per_account pass
-- gate: expect assert_cost_allocation_conserved pass
-- gate: expect assert_cost_allocation_coefficients_close pass
-- gate: expect assert_cost_allocation_frozen_consistent pass
-- konsol#269 WF1 built fixture (review M2): the model's real logic, built from staging.
-- Two Step-Down runs over two pool accounts, ZZ6000 and ZZ6100, with a 10,000,000.1234 pool.
-- Coefficients (the macro header's worked example): ZZIT -> ZZHR .2, ZZP1 .5, ZZP2 .3;
-- ZZHR passes on its .2 of ZZIT as ZZP1 .125, ZZP2 .075; ZZHR's own pool -> ZZP1 .625,
-- ZZP2 .375.
--   ZZRD  Declared Allocation Account ZZ6999, Freeze at Approval, ZZE1 P1. TB: ZZ6000
--         ZZIT 10,000,000.1234, ZZHR 400; ZZ6100 ZZIT 1000, ZZHR 600. ZZ6000 is relieved
--         exactly 10,000,400.1234, ZZ6100 exactly 1600, ZZ6999 carries 10,002,000.1234;
--         ZZHR's pass-through of ZZIT nets to zero on ZZ6999. The received lines of the
--         two pools share every key but pool_account (review M1).
--   ZZRO  Sender's Own Accounts, Follow Latest Data, ZZE2 P1. TB: ZZ6000 ZZIT
--         10,000,000.1234, ZZHR 400; ZZ6100 ZZIT 250, ZZHR 80. Every account nets to zero.
-- tables epm_gold.gold_scenario_trial_balance
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZRD','ZZRS1','Step-Down','dim_cost_center','Declared Allocation Account','ZZ6999','Freeze at Approval','ZZE1','ZZSC',2026,1),
('ZZRO','ZZRS2','Step-Down','dim_cost_center','Sender''s Own Accounts','','Follow Latest Data','ZZE2','ZZSC',2026,1);
INSERT INTO epm_staging.cost_allocation_run_accounts (parent, idx, main_account, declared_account) VALUES
('ZZRD',1,'ZZ6000',''),('ZZRD',2,'ZZ6100',''),
('ZZRO',1,'ZZ6000',''),('ZZRO',2,'ZZ6100','');
INSERT INTO epm_staging.cost_allocation_coefficients (run, origin_member, step, sender_member, receiver_member, driver, pool_coefficient, coefficient) VALUES
('ZZRD','ZZIT',1,'ZZIT','ZZHR','ZZ Headcount',1,0.2),
('ZZRD','ZZIT',1,'ZZIT','ZZP1','ZZ Headcount',1,0.5),
('ZZRD','ZZIT',1,'ZZIT','ZZP2','ZZ Headcount',1,0.3),
('ZZRD','ZZIT',2,'ZZHR','ZZP1','ZZ Headcount',0.2,0.125),
('ZZRD','ZZIT',2,'ZZHR','ZZP2','ZZ Headcount',0.2,0.075),
('ZZRD','ZZHR',2,'ZZHR','ZZP1','ZZ Headcount',1,0.625),
('ZZRD','ZZHR',2,'ZZHR','ZZP2','ZZ Headcount',1,0.375),
('ZZRO','ZZIT',1,'ZZIT','ZZHR','ZZ Headcount',1,0.2),
('ZZRO','ZZIT',1,'ZZIT','ZZP1','ZZ Headcount',1,0.5),
('ZZRO','ZZIT',1,'ZZIT','ZZP2','ZZ Headcount',1,0.3),
('ZZRO','ZZIT',2,'ZZHR','ZZP1','ZZ Headcount',0.2,0.125),
('ZZRO','ZZIT',2,'ZZHR','ZZP2','ZZ Headcount',0.2,0.075),
('ZZRO','ZZHR',2,'ZZHR','ZZP1','ZZ Headcount',1,0.625),
('ZZRO','ZZHR',2,'ZZHR','ZZP2','ZZ Headcount',1,0.375);
INSERT INTO epm_gold.gold_scenario_trial_balance (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, amount) VALUES
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZIT',10000000.1234),
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZHR',400),
('ZZSC','ZZE1',2026,1,'ZZ6100','ZZIT',1000),
('ZZSC','ZZE1',2026,1,'ZZ6100','ZZHR',600),
('ZZSC','ZZE2',2026,1,'ZZ6000','ZZIT',10000000.1234),
('ZZSC','ZZE2',2026,1,'ZZ6000','ZZHR',400),
('ZZSC','ZZE2',2026,1,'ZZ6100','ZZIT',250),
('ZZSC','ZZE2',2026,1,'ZZ6100','ZZHR',80);
