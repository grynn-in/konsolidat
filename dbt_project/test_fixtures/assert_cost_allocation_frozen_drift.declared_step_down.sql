-- gate: build gold_cost_allocation_frozen gold_cost_allocation assert_cost_allocation_frozen_drift
-- gate: expect gold_cost_allocation_frozen built
-- gate: expect gold_cost_allocation built
-- gate: expect assert_cost_allocation_frozen_drift pass
-- konsol#269 WF3 built fixture: frozen_drift in Declared Allocation Account mode with a
-- pass-through. ZZRD (Step-Down, Freeze at Approval, ZZE1 P1, ZZ6999) is frozen at the
-- TB it is built from, so nothing has drifted; a pass-through `sent` line on ZZ6999
-- must not be read as an origin pool (it would show as a drift).
-- tables epm_gold.gold_scenario_trial_balance
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZRD','ZZRS1','Step-Down','dim_cost_center','Declared Allocation Account','ZZ6999','Freeze at Approval','ZZE1','ZZSC',2026,1);
INSERT INTO epm_staging.cost_allocation_run_accounts (parent, idx, main_account, declared_account) VALUES
('ZZRD',1,'ZZ6000',''),('ZZRD',2,'ZZ6100','');
INSERT INTO epm_staging.cost_allocation_coefficients (run, origin_member, step, sender_member, receiver_member, driver, pool_coefficient, coefficient) VALUES
('ZZRD','ZZIT',1,'ZZIT','ZZHR','ZZ Headcount',1,0.2),
('ZZRD','ZZIT',1,'ZZIT','ZZP1','ZZ Headcount',1,0.5),
('ZZRD','ZZIT',1,'ZZIT','ZZP2','ZZ Headcount',1,0.3),
('ZZRD','ZZIT',2,'ZZHR','ZZP1','ZZ Headcount',0.2,0.125),
('ZZRD','ZZIT',2,'ZZHR','ZZP2','ZZ Headcount',0.2,0.075),
('ZZRD','ZZHR',2,'ZZHR','ZZP1','ZZ Headcount',1,0.625),
('ZZRD','ZZHR',2,'ZZHR','ZZP2','ZZ Headcount',1,0.375);
INSERT INTO epm_gold.gold_scenario_trial_balance (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, amount) VALUES
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZIT',10000000.1234),
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZHR',400),
('ZZSC','ZZE1',2026,1,'ZZ6100','ZZIT',1000),
('ZZSC','ZZE1',2026,1,'ZZ6100','ZZHR',600);
