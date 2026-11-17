-- gate: build gold_cost_allocation_frozen gold_cost_allocation assert_cost_allocation_expected_values
-- gate: expect gold_cost_allocation built
-- gate: expect assert_cost_allocation_expected_values pass
-- konsol#269 RF5 (review finding 5): the worked example's VALUES are asserted, not only conserved. Run ZZEV carries
-- the RC6 reciprocal coefficients (IT 1,000 and HR 400 on ZZ6000, Declared Allocation Account ZZ6999). On ZZ6999:
-- Sales +885, Ops +515, IT 0, HR 0; and IT -> HR gross 725 = own 500 + pass 225.
-- tables epm_gold.gold_scenario_trial_balance, epm_gold.gold_cost_allocation_frozen
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZEV','ZZRS1','Reciprocal','dim_cost_center','Declared Allocation Account','ZZ6999','Follow Latest Data','ZZE1','ZZSC',2026,1);
INSERT INTO epm_staging.cost_allocation_run_accounts (parent, idx, main_account, declared_account) VALUES
('ZZEV',1,'ZZ6000','');
INSERT INTO epm_staging.cost_allocation_coefficients (run, origin_member, step, sender_member, receiver_member, driver, hop_kind, pool_coefficient, coefficient) VALUES
('ZZEV','ZZIT',1,'ZZIT','ZZHR','ZZ Tickets','own',1.000000000000,0.500000000000),
('ZZEV','ZZIT',1,'ZZIT','ZZSA','ZZ Tickets','own',1.000000000000,0.300000000000),
('ZZEV','ZZIT',1,'ZZIT','ZZOP','ZZ Tickets','own',1.000000000000,0.200000000000),
('ZZEV','ZZIT',1,'ZZIT','ZZHR','ZZ Tickets','pass',0.250000000000,0.125000000000),
('ZZEV','ZZIT',1,'ZZIT','ZZSA','ZZ Tickets','pass',0.250000000000,0.075000000000),
('ZZEV','ZZIT',1,'ZZIT','ZZOP','ZZ Tickets','pass',0.250000000000,0.050000000000),
('ZZEV','ZZIT',2,'ZZHR','ZZIT','ZZ Headcount','pass',0.625000000000,0.250000000000),
('ZZEV','ZZIT',2,'ZZHR','ZZSA','ZZ Headcount','pass',0.625000000000,0.250000000000),
('ZZEV','ZZIT',2,'ZZHR','ZZOP','ZZ Headcount','pass',0.625000000000,0.125000000000),
('ZZEV','ZZHR',1,'ZZIT','ZZHR','ZZ Tickets','pass',0.500000000000,0.250000000000),
('ZZEV','ZZHR',1,'ZZIT','ZZSA','ZZ Tickets','pass',0.500000000000,0.150000000000),
('ZZEV','ZZHR',1,'ZZIT','ZZOP','ZZ Tickets','pass',0.500000000000,0.100000000000),
('ZZEV','ZZHR',2,'ZZHR','ZZIT','ZZ Headcount','own',1.000000000000,0.400000000000),
('ZZEV','ZZHR',2,'ZZHR','ZZSA','ZZ Headcount','own',1.000000000000,0.400000000000),
('ZZEV','ZZHR',2,'ZZHR','ZZOP','ZZ Headcount','own',1.000000000000,0.200000000000),
('ZZEV','ZZHR',2,'ZZHR','ZZIT','ZZ Headcount','pass',0.250000000000,0.100000000000),
('ZZEV','ZZHR',2,'ZZHR','ZZSA','ZZ Headcount','pass',0.250000000000,0.100000000000),
('ZZEV','ZZHR',2,'ZZHR','ZZOP','ZZ Headcount','pass',0.250000000000,0.050000000000);
INSERT INTO epm_gold.gold_scenario_trial_balance (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, amount) VALUES
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZIT',1000),
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZHR',400);
