-- gate: build gold_cost_allocation_frozen gold_cost_allocation assert_cost_allocation_balanced_per_account
-- gate: expect gold_cost_allocation_frozen built
-- gate: expect gold_cost_allocation built
-- gate: expect assert_cost_allocation_balanced_per_account flag 6
-- konsol#269 RC6 must-flag fixture, built: Reciprocal, Declared Allocation Account ZZ6999, pool account ZZ6000 (IT 1,000, HR 400),
-- every `pass` row tagged `own`. The macro then books each passed-on `sent` line on the pool account, as an origin's relief
-- (a pass `sent` line belongs on the allocation account). Expected 6 rows:
--   origin not relieved by exactly its pool, 4: ZZIT on ZZ6000 (-1,250 for a pool of 1,000), ZZHR on ZZ6000 (-500 for 400),
--   and on ZZ6999 where ZZIT (+250) and ZZHR (+100) receive their own cost back and, no longer passing it on there, hold it;
--   account balance, 2: ZZ6000 is over-relieved and ZZ6999 over-carries by the same amount.
-- tables epm_gold.gold_scenario_trial_balance, epm_gold.gold_cost_allocation_frozen
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZRX','ZZRS1','Reciprocal','dim_cost_center','Declared Allocation Account','ZZ6999','Follow Latest Data','ZZE1','ZZSC',2026,1);
INSERT INTO epm_staging.cost_allocation_run_accounts (parent, idx, main_account, declared_account) VALUES
('ZZRX',1,'ZZ6000','');
INSERT INTO epm_staging.cost_allocation_coefficients (run, origin_member, step, sender_member, receiver_member, driver, hop_kind, pool_coefficient, coefficient) VALUES
('ZZRX','ZZIT',1,'ZZIT','ZZHR','ZZ Tickets','own',1.000000000000,0.500000000000),
('ZZRX','ZZIT',1,'ZZIT','ZZSA','ZZ Tickets','own',1.000000000000,0.300000000000),
('ZZRX','ZZIT',1,'ZZIT','ZZOP','ZZ Tickets','own',1.000000000000,0.200000000000),
('ZZRX','ZZIT',1,'ZZIT','ZZHR','ZZ Tickets','own',0.250000000000,0.125000000000),
('ZZRX','ZZIT',1,'ZZIT','ZZSA','ZZ Tickets','own',0.250000000000,0.075000000000),
('ZZRX','ZZIT',1,'ZZIT','ZZOP','ZZ Tickets','own',0.250000000000,0.050000000000),
('ZZRX','ZZIT',2,'ZZHR','ZZIT','ZZ Headcount','own',0.625000000000,0.250000000000),
('ZZRX','ZZIT',2,'ZZHR','ZZSA','ZZ Headcount','own',0.625000000000,0.250000000000),
('ZZRX','ZZIT',2,'ZZHR','ZZOP','ZZ Headcount','own',0.625000000000,0.125000000000),
('ZZRX','ZZHR',1,'ZZIT','ZZHR','ZZ Tickets','own',0.500000000000,0.250000000000),
('ZZRX','ZZHR',1,'ZZIT','ZZSA','ZZ Tickets','own',0.500000000000,0.150000000000),
('ZZRX','ZZHR',1,'ZZIT','ZZOP','ZZ Tickets','own',0.500000000000,0.100000000000),
('ZZRX','ZZHR',2,'ZZHR','ZZIT','ZZ Headcount','own',1.000000000000,0.400000000000),
('ZZRX','ZZHR',2,'ZZHR','ZZSA','ZZ Headcount','own',1.000000000000,0.400000000000),
('ZZRX','ZZHR',2,'ZZHR','ZZOP','ZZ Headcount','own',1.000000000000,0.200000000000),
('ZZRX','ZZHR',2,'ZZHR','ZZIT','ZZ Headcount','own',0.250000000000,0.100000000000),
('ZZRX','ZZHR',2,'ZZHR','ZZSA','ZZ Headcount','own',0.250000000000,0.100000000000),
('ZZRX','ZZHR',2,'ZZHR','ZZOP','ZZ Headcount','own',0.250000000000,0.050000000000);
INSERT INTO epm_gold.gold_scenario_trial_balance (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, amount) VALUES
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZIT',1000),
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZHR',400);
