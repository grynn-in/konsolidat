-- gate: build gold_cost_allocation_frozen gold_cost_allocation assert_cost_allocation_expected_values assert_cost_allocation_conserved assert_cost_allocation_coefficients_close assert_cost_allocation_balanced_per_account assert_cost_allocation_sender_relieved_once assert_cost_allocation_hop_kind_valid assert_cost_allocation_basis_valid assert_cost_allocation_amounts assert_cost_allocation_frozen_consistent assert_cost_allocation_frozen_drift
-- gate: expect gold_cost_allocation built
-- gate: expect assert_cost_allocation_expected_values pass
-- gate: expect assert_cost_allocation_conserved assert_cost_allocation_coefficients_close assert_cost_allocation_balanced_per_account assert_cost_allocation_sender_relieved_once assert_cost_allocation_hop_kind_valid assert_cost_allocation_basis_valid assert_cost_allocation_amounts assert_cost_allocation_frozen_consistent assert_cost_allocation_frozen_drift pass
-- konsol#269 2b-2 W5: Reciprocal with a Declared Rate sender, values asserted. Run ZZEQ, Reciprocal, Declared
-- Allocation Account ZZ6999, pools on ZZ6000: ZZIT 1,000, ZZHR 400, ZZFM 300. ZZIT charges 50 per ticket
-- (ZZHR 5, ZZSA 8, ZZOP 6); ZZHR (share) by headcount ZZFM 4, ZZSA 1; ZZFM (share) by area ZZHR 5, ZZIT 1,
-- ZZSA 1, ZZOP 1. ZZHR and ZZFM are the reciprocal pair, solved over the share senders only; ZZFM also sends
-- to ZZIT, a rate sender, where cost of every origin stops (its own returning ticket included).
--   Sent: ZZIT 950 (50 x 19), ZZHR 1,675, ZZFM 1,640. Received: ZZIT 205 (50 of its own, 80 of ZZHR's, 75
--   of ZZFM's), ZZHR 1,275, ZZFM 1,340. On ZZ6999: ZZSA 940, ZZOP 505, ZZIT -745 (= 205 - 950), ZZHR 0,
--   ZZFM 0; gross ZZIT -> ZZHR own 250, ZZFM -> ZZIT pass 205 (everything ZZIT absorbs). ZZIT's absorption
--   variance 255 = 1,000 + 205 - 950 stays on ZZ6000 for its own model. Totals: 940 + 505 + 255 = 1,700.
-- The 27 coefficient rows are konsol's (cost_allocation_model.coefficient_rows, Reciprocal), not derived by
-- hand; konsol's test_rate_reciprocal_worked_example_end_to_end_money pins the same money.
-- tables epm_gold.gold_scenario_trial_balance, epm_gold.gold_cost_allocation_frozen
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZEQ','ZZRS1','Reciprocal','dim_cost_center','Declared Allocation Account','ZZ6999','Follow Latest Data','ZZE1','ZZSC',2026,1);
INSERT INTO epm_staging.cost_allocation_run_accounts (parent, idx, main_account, declared_account) VALUES
('ZZEQ',1,'ZZ6000','');
INSERT INTO epm_staging.cost_allocation_run_weights (parent, idx, step, sender_member, receiver_member, driver, statistic, value_period, carried_forward, driver_value, source, effective_from, basis, rate, rate_from) VALUES
('ZZEQ',1,1,'ZZIT','ZZHR','ZZ Tickets','ZZ Tickets',1,0,5,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZEQ',2,1,'ZZIT','ZZSA','ZZ Tickets','ZZ Tickets',1,0,8,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZEQ',3,1,'ZZIT','ZZOP','ZZ Tickets','ZZ Tickets',1,0,6,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZEQ',4,2,'ZZHR','ZZFM','ZZ Headcount','ZZ Headcount',1,0,4,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01'),
('ZZEQ',5,2,'ZZHR','ZZSA','ZZ Headcount','ZZ Headcount',1,0,1,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01'),
('ZZEQ',6,3,'ZZFM','ZZHR','ZZ Area','ZZ Area',1,0,5,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01'),
('ZZEQ',7,3,'ZZFM','ZZIT','ZZ Area','ZZ Area',1,0,1,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01'),
('ZZEQ',8,3,'ZZFM','ZZSA','ZZ Area','ZZ Area',1,0,1,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01'),
('ZZEQ',9,3,'ZZFM','ZZOP','ZZ Area','ZZ Area',1,0,1,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01');
INSERT INTO epm_staging.cost_allocation_coefficients (run, origin_member, step, sender_member, receiver_member, driver, hop_kind, pool_coefficient, coefficient) VALUES
('ZZEQ','ZZIT',1,'ZZIT','ZZHR','ZZ Tickets','own',19.000000000000,5.000000000000),
('ZZEQ','ZZIT',1,'ZZIT','ZZSA','ZZ Tickets','own',19.000000000000,8.000000000000),
('ZZEQ','ZZIT',1,'ZZIT','ZZOP','ZZ Tickets','own',19.000000000000,6.000000000000),
('ZZEQ','ZZIT',2,'ZZHR','ZZFM','ZZ Headcount','pass',10.000000000000,8.000000000000),
('ZZEQ','ZZIT',2,'ZZHR','ZZSA','ZZ Headcount','pass',10.000000000000,2.000000000000),
('ZZEQ','ZZIT',3,'ZZFM','ZZHR','ZZ Area','pass',8.000000000000,5.000000000000),
('ZZEQ','ZZIT',3,'ZZFM','ZZIT','ZZ Area','pass',8.000000000000,1.000000000000),
('ZZEQ','ZZIT',3,'ZZFM','ZZSA','ZZ Area','pass',8.000000000000,1.000000000000),
('ZZEQ','ZZIT',3,'ZZFM','ZZOP','ZZ Area','pass',8.000000000000,1.000000000000),
('ZZEQ','ZZHR',2,'ZZHR','ZZFM','ZZ Headcount','own',1.000000000000,0.800000000000),
('ZZEQ','ZZHR',2,'ZZHR','ZZSA','ZZ Headcount','own',1.000000000000,0.200000000000),
('ZZEQ','ZZHR',2,'ZZHR','ZZFM','ZZ Headcount','pass',1.000000000000,0.800000000000),
('ZZEQ','ZZHR',2,'ZZHR','ZZSA','ZZ Headcount','pass',1.000000000000,0.200000000000),
('ZZEQ','ZZHR',3,'ZZFM','ZZHR','ZZ Area','pass',1.600000000000,1.000000000000),
('ZZEQ','ZZHR',3,'ZZFM','ZZIT','ZZ Area','pass',1.600000000000,0.200000000000),
('ZZEQ','ZZHR',3,'ZZFM','ZZSA','ZZ Area','pass',1.600000000000,0.200000000000),
('ZZEQ','ZZHR',3,'ZZFM','ZZOP','ZZ Area','pass',1.600000000000,0.200000000000),
('ZZEQ','ZZFM',2,'ZZHR','ZZFM','ZZ Headcount','pass',1.250000000000,1.000000000000),
('ZZEQ','ZZFM',2,'ZZHR','ZZSA','ZZ Headcount','pass',1.250000000000,0.250000000000),
('ZZEQ','ZZFM',3,'ZZFM','ZZHR','ZZ Area','own',1.000000000000,0.625000000000),
('ZZEQ','ZZFM',3,'ZZFM','ZZIT','ZZ Area','own',1.000000000000,0.125000000000),
('ZZEQ','ZZFM',3,'ZZFM','ZZSA','ZZ Area','own',1.000000000000,0.125000000000),
('ZZEQ','ZZFM',3,'ZZFM','ZZOP','ZZ Area','own',1.000000000000,0.125000000000),
('ZZEQ','ZZFM',3,'ZZFM','ZZHR','ZZ Area','pass',1.000000000000,0.625000000000),
('ZZEQ','ZZFM',3,'ZZFM','ZZIT','ZZ Area','pass',1.000000000000,0.125000000000),
('ZZEQ','ZZFM',3,'ZZFM','ZZSA','ZZ Area','pass',1.000000000000,0.125000000000),
('ZZEQ','ZZFM',3,'ZZFM','ZZOP','ZZ Area','pass',1.000000000000,0.125000000000);
INSERT INTO epm_gold.gold_scenario_trial_balance (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, amount) VALUES
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZIT',1000),
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZHR',400),
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZFM',300);
