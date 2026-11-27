-- gate: build gold_cost_allocation_frozen gold_cost_allocation assert_cost_allocation_balanced_per_account assert_cost_allocation_conserved assert_cost_allocation_coefficients_close assert_cost_allocation_frozen_consistent assert_cost_allocation_sender_relieved_once assert_cost_allocation_hop_kind_valid assert_cost_allocation_basis_valid assert_cost_allocation_amounts
-- gate: expect gold_cost_allocation_frozen built
-- gate: expect gold_cost_allocation built
-- gate: expect assert_cost_allocation_balanced_per_account pass
-- gate: expect assert_cost_allocation_conserved pass
-- gate: expect assert_cost_allocation_coefficients_close pass
-- gate: expect assert_cost_allocation_frozen_consistent pass
-- gate: expect assert_cost_allocation_sender_relieved_once pass
-- gate: expect assert_cost_allocation_hop_kind_valid pass
-- gate: expect assert_cost_allocation_basis_valid pass
-- gate: expect assert_cost_allocation_amounts pass
-- konsol#269 2b-2 W5 built fixture: the model's real logic with a Declared Rate step, built from staging.
-- Run ZZRT is the plan's worked example (section 3): Step-Down, Declared Allocation Account ZZ6999,
-- Follow Latest Data, ZZE1 P1, pool account ZZ6000 (ZZIT 1,000, ZZHR 400).
--   Step 1: ZZIT charges a declared rate of 50 per ticket; tickets ZZHR 5, ZZSA 8, ZZOP 6 (the
--   weight rows carry basis 'Declared Rate', rate 50 and the rate window). Coefficients are in
--   units (own pool 19). The macro reads the rate as ZZIT's origin_amount and books its own relief
--   on the ALLOCATION account: ZZ6999 at ZZIT -950 (250 + 400 + 300); ZZIT's pool on ZZ6000 is untouched.
--   Step 2: ZZHR (share, pool 400) passes the 250 it received on 5/8 : 3/8 and relieves its own 400.
-- Expected: ZZ6999 ZZSA +806.25, ZZOP +543.75, ZZIT -950, ZZHR 0; ZZ6000 ZZHR -400. Every line of
-- origin ZZIT carries basis 'Declared Rate', every line of origin ZZHR 'Share of Pool'.
-- tables epm_gold.gold_scenario_trial_balance, epm_gold.gold_cost_allocation_frozen
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZRT','ZZRS1','Step-Down','dim_cost_center','Declared Allocation Account','ZZ6999','Follow Latest Data','ZZE1','ZZSC',2026,1);
INSERT INTO epm_staging.cost_allocation_run_accounts (parent, idx, main_account, declared_account) VALUES
('ZZRT',1,'ZZ6000','');
INSERT INTO epm_staging.cost_allocation_run_weights (parent, idx, step, sender_member, receiver_member, driver, statistic, value_period, carried_forward, driver_value, source, effective_from, basis, rate, rate_from) VALUES
('ZZRT',1,1,'ZZIT','ZZHR','ZZ Tickets','ZZ Tickets',1,0,5,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRT',2,1,'ZZIT','ZZSA','ZZ Tickets','ZZ Tickets',1,0,8,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRT',3,1,'ZZIT','ZZOP','ZZ Tickets','ZZ Tickets',1,0,6,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRT',4,2,'ZZHR','ZZSA','ZZ Headcount','ZZ Headcount',1,0,5,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01'),
('ZZRT',5,2,'ZZHR','ZZOP','ZZ Headcount','ZZ Headcount',1,0,3,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01');
INSERT INTO epm_staging.cost_allocation_coefficients (run, origin_member, step, sender_member, receiver_member, driver, hop_kind, pool_coefficient, coefficient) VALUES
('ZZRT','ZZIT',1,'ZZIT','ZZHR','ZZ Tickets','own',19.000000000000,5.000000000000),
('ZZRT','ZZIT',1,'ZZIT','ZZSA','ZZ Tickets','own',19.000000000000,8.000000000000),
('ZZRT','ZZIT',1,'ZZIT','ZZOP','ZZ Tickets','own',19.000000000000,6.000000000000),
('ZZRT','ZZIT',2,'ZZHR','ZZSA','ZZ Headcount','pass',5.000000000000,3.125000000000),
('ZZRT','ZZIT',2,'ZZHR','ZZOP','ZZ Headcount','pass',5.000000000000,1.875000000000),
('ZZRT','ZZHR',2,'ZZHR','ZZSA','ZZ Headcount','own',1.000000000000,0.625000000000),
('ZZRT','ZZHR',2,'ZZHR','ZZOP','ZZ Headcount','own',1.000000000000,0.375000000000);
INSERT INTO epm_gold.gold_scenario_trial_balance (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, amount) VALUES
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZIT',1000),
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZHR',400);
