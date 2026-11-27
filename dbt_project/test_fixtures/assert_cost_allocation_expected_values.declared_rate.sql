-- gate: build gold_cost_allocation_frozen gold_cost_allocation assert_cost_allocation_expected_values assert_cost_allocation_conserved assert_cost_allocation_coefficients_close assert_cost_allocation_balanced_per_account assert_cost_allocation_sender_relieved_once assert_cost_allocation_hop_kind_valid assert_cost_allocation_basis_valid assert_cost_allocation_amounts assert_cost_allocation_frozen_consistent assert_cost_allocation_frozen_drift
-- gate: expect gold_cost_allocation built
-- gate: expect assert_cost_allocation_expected_values pass
-- gate: expect assert_cost_allocation_conserved assert_cost_allocation_coefficients_close assert_cost_allocation_balanced_per_account assert_cost_allocation_sender_relieved_once assert_cost_allocation_hop_kind_valid assert_cost_allocation_basis_valid assert_cost_allocation_amounts assert_cost_allocation_frozen_consistent assert_cost_allocation_frozen_drift pass
-- konsol#269 2b-2 W5: the plan's declared-rate worked example (section 3) has its VALUES asserted. Run ZZER,
-- Step-Down, Declared Allocation Account ZZ6999, ZZ6000 pools ZZIT 1,000 and ZZHR 400. ZZIT charges 50 per
-- ticket (ZZHR 5, ZZSA 8, ZZOP 6: 950 in all); ZZHR holds 400 + 250 = 650 and splits it 5/8 : 3/8.
-- On ZZ6999: ZZSA 806.25, ZZOP 543.75, ZZIT -950 (its relief, on the allocation account), ZZHR 0; gross
-- ZZIT -> ZZHR own 250 and ZZHR -> ZZSA pass 156.25 (3.125 tickets x 50). ZZIT's absorption variance, 50,
-- is pool 1,000 + received 0 - charged 950, left on ZZ6000 (konsol#269 Q5 A: reported by its own model).
-- The coefficient rows are konsol's (cost_allocation_model.coefficient_rows), not derived by hand.
-- tables epm_gold.gold_scenario_trial_balance, epm_gold.gold_cost_allocation_frozen
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZER','ZZRS1','Step-Down','dim_cost_center','Declared Allocation Account','ZZ6999','Follow Latest Data','ZZE1','ZZSC',2026,1);
INSERT INTO epm_staging.cost_allocation_run_accounts (parent, idx, main_account, declared_account) VALUES
('ZZER',1,'ZZ6000','');
INSERT INTO epm_staging.cost_allocation_run_weights (parent, idx, step, sender_member, receiver_member, driver, statistic, value_period, carried_forward, driver_value, source, effective_from, basis, rate, rate_from) VALUES
('ZZER',1,1,'ZZIT','ZZHR','ZZ Tickets','ZZ Tickets',1,0,5,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZER',2,1,'ZZIT','ZZSA','ZZ Tickets','ZZ Tickets',1,0,8,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZER',3,1,'ZZIT','ZZOP','ZZ Tickets','ZZ Tickets',1,0,6,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZER',4,2,'ZZHR','ZZSA','ZZ Headcount','ZZ Headcount',1,0,5,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01'),
('ZZER',5,2,'ZZHR','ZZOP','ZZ Headcount','ZZ Headcount',1,0,3,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01');
INSERT INTO epm_staging.cost_allocation_coefficients (run, origin_member, step, sender_member, receiver_member, driver, hop_kind, pool_coefficient, coefficient) VALUES
('ZZER','ZZIT',1,'ZZIT','ZZHR','ZZ Tickets','own',19.000000000000,5.000000000000),
('ZZER','ZZIT',1,'ZZIT','ZZSA','ZZ Tickets','own',19.000000000000,8.000000000000),
('ZZER','ZZIT',1,'ZZIT','ZZOP','ZZ Tickets','own',19.000000000000,6.000000000000),
('ZZER','ZZIT',2,'ZZHR','ZZSA','ZZ Headcount','pass',5.000000000000,3.125000000000),
('ZZER','ZZIT',2,'ZZHR','ZZOP','ZZ Headcount','pass',5.000000000000,1.875000000000),
('ZZER','ZZHR',2,'ZZHR','ZZSA','ZZ Headcount','own',1.000000000000,0.625000000000),
('ZZER','ZZHR',2,'ZZHR','ZZOP','ZZ Headcount','own',1.000000000000,0.375000000000);
INSERT INTO epm_gold.gold_scenario_trial_balance (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, amount) VALUES
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZIT',1000),
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZHR',400);
