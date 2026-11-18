-- gate: build gold_cost_allocation_frozen gold_cost_allocation assert_cost_allocation_expected_values
-- gate: expect gold_cost_allocation built
-- gate: expect assert_cost_allocation_expected_values flag 3
-- konsol#269 RF5 must-flag: run ZZEW holds STEP-DOWN's coefficients for the same pools (IT first; HR never sends back to IT;
-- HR's 900 splits Sales .6 / Ops .4). Money is conserved and every other cost allocation test passes, but the numbers are not
-- the reciprocal ones. 3 rows: Sales 840 (expected 885), Ops 560 (expected 515), IT -> HR pass 0 (expected 225).
-- tables epm_gold.gold_scenario_trial_balance, epm_gold.gold_cost_allocation_frozen
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZEW','ZZRS1','Reciprocal','dim_cost_center','Declared Allocation Account','ZZ6999','Follow Latest Data','ZZE1','ZZSC',2026,1);
INSERT INTO epm_staging.cost_allocation_run_accounts (parent, idx, main_account, declared_account) VALUES
('ZZEW',1,'ZZ6000','');
INSERT INTO epm_staging.cost_allocation_coefficients (run, origin_member, step, sender_member, receiver_member, driver, hop_kind, pool_coefficient, coefficient) VALUES
('ZZEW','ZZIT',1,'ZZIT','ZZHR','ZZ Tickets','own',1.000000000000,0.500000000000),
('ZZEW','ZZIT',1,'ZZIT','ZZSA','ZZ Tickets','own',1.000000000000,0.300000000000),
('ZZEW','ZZIT',1,'ZZIT','ZZOP','ZZ Tickets','own',1.000000000000,0.200000000000),
('ZZEW','ZZIT',2,'ZZHR','ZZSA','ZZ Headcount','pass',0.500000000000,0.300000000000),
('ZZEW','ZZIT',2,'ZZHR','ZZOP','ZZ Headcount','pass',0.500000000000,0.200000000000),
('ZZEW','ZZHR',2,'ZZHR','ZZSA','ZZ Headcount','own',1.000000000000,0.600000000000),
('ZZEW','ZZHR',2,'ZZHR','ZZOP','ZZ Headcount','own',1.000000000000,0.400000000000);
INSERT INTO epm_gold.gold_scenario_trial_balance (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, amount) VALUES
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZIT',1000),
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZHR',400);
