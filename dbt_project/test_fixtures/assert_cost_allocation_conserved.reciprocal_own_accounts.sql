-- gate: build gold_cost_allocation_frozen gold_cost_allocation assert_cost_allocation_conserved assert_cost_allocation_coefficients_close assert_cost_allocation_balanced_per_account assert_cost_allocation_sender_relieved_once assert_cost_allocation_amounts assert_cost_allocation_frozen_consistent assert_cost_allocation_frozen_drift
-- gate: expect gold_cost_allocation_frozen built
-- gate: expect gold_cost_allocation built
-- gate: expect assert_cost_allocation_conserved pass
-- gate: expect assert_cost_allocation_coefficients_close pass
-- gate: expect assert_cost_allocation_balanced_per_account pass
-- gate: expect assert_cost_allocation_sender_relieved_once pass
-- gate: expect assert_cost_allocation_amounts pass
-- gate: expect assert_cost_allocation_frozen_consistent pass
-- gate: expect assert_cost_allocation_frozen_drift pass
-- konsol#269 RC6 clean fixture: Reciprocal, Sender's Own Accounts, Follow Latest Data, one pool account ZZ6000.
-- Worked example (konsol#269 RC1; the numbers are produced by konsol's cost_allocation_model,
-- coefficient_rows(..., 'Reciprocal'), not derived by hand). Service departments ZZIT (IT) and ZZHR (HR)
-- serve each other; ZZSA (Sales) and ZZOP (Ops) never send.
--   IT own 1,000, driver ZZ Tickets: HR 5, Sales 3, Ops 2.   HR own 400, driver ZZ Headcount: IT 4, Sales 4, Ops 2.
--   T_IT = 1,000 + .4 T_HR and T_HR = 400 + .5 T_IT, so T_IT = 1,450 and T_HR = 1,125.
--   Final cost: Sales 885 (625 of IT's pool + 260 of HR's), Ops 515 (375 + 140), IT 0, HR 0; total 1,400.
-- The coefficient rows carry hop_kind: IT's `own` unit leaves IT; what comes back from HR to IT is a `pass`
-- hop whose sender is the origin IT itself, and HR's pool carries `pass` rows at IT. A predicate that reads
-- sender = origin as own relief flags this correct run.
-- Expected: all seven allocation tests pass (conserved, coefficients_close, balanced_per_account,
-- sender_relieved_once, amounts, and the frozen checks, vacuous here).
-- tables epm_gold.gold_scenario_trial_balance, epm_gold.gold_cost_allocation_frozen
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZRR','ZZRS1','Reciprocal','dim_cost_center','Sender''s Own Accounts','','Follow Latest Data','ZZE1','ZZSC',2026,1);
INSERT INTO epm_staging.cost_allocation_run_accounts (parent, idx, main_account, declared_account) VALUES
('ZZRR',1,'ZZ6000','');
INSERT INTO epm_staging.cost_allocation_coefficients (run, origin_member, step, sender_member, receiver_member, driver, hop_kind, pool_coefficient, coefficient) VALUES
('ZZRR','ZZIT',1,'ZZIT','ZZHR','ZZ Tickets','own',1.000000000000,0.500000000000),
('ZZRR','ZZIT',1,'ZZIT','ZZSA','ZZ Tickets','own',1.000000000000,0.300000000000),
('ZZRR','ZZIT',1,'ZZIT','ZZOP','ZZ Tickets','own',1.000000000000,0.200000000000),
('ZZRR','ZZIT',1,'ZZIT','ZZHR','ZZ Tickets','pass',0.250000000000,0.125000000000),
('ZZRR','ZZIT',1,'ZZIT','ZZSA','ZZ Tickets','pass',0.250000000000,0.075000000000),
('ZZRR','ZZIT',1,'ZZIT','ZZOP','ZZ Tickets','pass',0.250000000000,0.050000000000),
('ZZRR','ZZIT',2,'ZZHR','ZZIT','ZZ Headcount','pass',0.625000000000,0.250000000000),
('ZZRR','ZZIT',2,'ZZHR','ZZSA','ZZ Headcount','pass',0.625000000000,0.250000000000),
('ZZRR','ZZIT',2,'ZZHR','ZZOP','ZZ Headcount','pass',0.625000000000,0.125000000000),
('ZZRR','ZZHR',1,'ZZIT','ZZHR','ZZ Tickets','pass',0.500000000000,0.250000000000),
('ZZRR','ZZHR',1,'ZZIT','ZZSA','ZZ Tickets','pass',0.500000000000,0.150000000000),
('ZZRR','ZZHR',1,'ZZIT','ZZOP','ZZ Tickets','pass',0.500000000000,0.100000000000),
('ZZRR','ZZHR',2,'ZZHR','ZZIT','ZZ Headcount','own',1.000000000000,0.400000000000),
('ZZRR','ZZHR',2,'ZZHR','ZZSA','ZZ Headcount','own',1.000000000000,0.400000000000),
('ZZRR','ZZHR',2,'ZZHR','ZZOP','ZZ Headcount','own',1.000000000000,0.200000000000),
('ZZRR','ZZHR',2,'ZZHR','ZZIT','ZZ Headcount','pass',0.250000000000,0.100000000000),
('ZZRR','ZZHR',2,'ZZHR','ZZSA','ZZ Headcount','pass',0.250000000000,0.100000000000),
('ZZRR','ZZHR',2,'ZZHR','ZZOP','ZZ Headcount','pass',0.250000000000,0.050000000000);
INSERT INTO epm_gold.gold_scenario_trial_balance (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, amount) VALUES
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZIT',1000),
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZHR',400);
