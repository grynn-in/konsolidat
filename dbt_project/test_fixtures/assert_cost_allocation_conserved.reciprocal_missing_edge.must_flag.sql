-- gate: build gold_cost_allocation_frozen gold_cost_allocation assert_cost_allocation_conserved
-- gate: expect gold_cost_allocation_frozen built
-- gate: expect gold_cost_allocation built
-- gate: expect assert_cost_allocation_conserved flag 1
-- konsol#269 RC6 must-flag fixture, built: the Reciprocal worked example missing the service-to-service edge ZZHR -> ZZIT.
-- The rows with sender ZZHR and receiver ZZIT are gone (HR's own unit to IT and the pass of IT's cost back to IT), and so
-- are the `pass` rows ZZIT sends for the cost that came back. Origin ZZIT: HR holds .625 of the pool but sends on only
-- .25 + .125, so the members that never send (Sales .3 + .25, Ops .2 + .125) receive 875 of the pool of 1,000: 1 row.
-- Origin ZZHR is untouched in total (its finals still sum to 1), so it is not flagged. The lines still sum to zero,
-- which is why only part 2 of the test fires.
-- tables epm_gold.gold_scenario_trial_balance, epm_gold.gold_cost_allocation_frozen
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZRY','ZZRS1','Reciprocal','dim_cost_center','Sender''s Own Accounts','','Follow Latest Data','ZZE1','ZZSC',2026,1);
INSERT INTO epm_staging.cost_allocation_run_accounts (parent, idx, main_account, declared_account) VALUES
('ZZRY',1,'ZZ6000','');
INSERT INTO epm_staging.cost_allocation_coefficients (run, origin_member, step, sender_member, receiver_member, driver, hop_kind, pool_coefficient, coefficient) VALUES
('ZZRY','ZZIT',1,'ZZIT','ZZHR','ZZ Tickets','own',1.000000000000,0.500000000000),
('ZZRY','ZZIT',1,'ZZIT','ZZSA','ZZ Tickets','own',1.000000000000,0.300000000000),
('ZZRY','ZZIT',1,'ZZIT','ZZOP','ZZ Tickets','own',1.000000000000,0.200000000000),
('ZZRY','ZZIT',2,'ZZHR','ZZSA','ZZ Headcount','pass',0.625000000000,0.250000000000),
('ZZRY','ZZIT',2,'ZZHR','ZZOP','ZZ Headcount','pass',0.625000000000,0.125000000000),
('ZZRY','ZZHR',1,'ZZIT','ZZHR','ZZ Tickets','pass',0.500000000000,0.250000000000),
('ZZRY','ZZHR',1,'ZZIT','ZZSA','ZZ Tickets','pass',0.500000000000,0.150000000000),
('ZZRY','ZZHR',1,'ZZIT','ZZOP','ZZ Tickets','pass',0.500000000000,0.100000000000),
('ZZRY','ZZHR',2,'ZZHR','ZZSA','ZZ Headcount','own',1.000000000000,0.400000000000),
('ZZRY','ZZHR',2,'ZZHR','ZZOP','ZZ Headcount','own',1.000000000000,0.200000000000),
('ZZRY','ZZHR',2,'ZZHR','ZZSA','ZZ Headcount','pass',0.250000000000,0.100000000000),
('ZZRY','ZZHR',2,'ZZHR','ZZOP','ZZ Headcount','pass',0.250000000000,0.050000000000);
INSERT INTO epm_gold.gold_scenario_trial_balance (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, amount) VALUES
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZIT',1000),
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZHR',400);
