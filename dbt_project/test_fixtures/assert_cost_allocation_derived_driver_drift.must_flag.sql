-- gate: expect assert_cost_allocation_derived_driver_drift flag 3
-- konsol#269 phase 2b-1 W3 must-flag fixture (warn severity). Run ZZR1 (ZZE1, ZZSC, 2026 P3),
-- the same drivers as the clean fixture, with the trial balance changed after Compute.
-- idx 1 flagged: ZZP1 revenue was -100 at Compute (weight 100); the TB now says -120 -> 120.
-- idx 2 ok: weight 300.00000001 against -300 -> 300: inside the 0.0000001 tolerance.
-- idx 3 flagged: ZZ Units ZZP1 was 10 + 5 = 15; a ZZ7100 row of 3 was posted since -> 18.
-- idx 4 ok: ZZP2 is a real zero (a 0 row exists) and the weight is 0.
-- idx 5 flagged: ZZP9 has no trial balance row at all; at Compute it had one (weight 4).
-- idx 6 ok: a statistic row whose value has nothing to do with the TB is not a derived row.
-- tables epm_gold.gold_scenario_trial_balance
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZR1','ZZRS1','Step-Down','dim_cost_center','Sender''s Own Accounts','','Follow Latest Data','ZZE1','ZZSC',2026,3);
INSERT INTO epm_staging.cost_allocation_run_driver_accounts (parent, idx, driver, main_account, value_sign) VALUES
('ZZR1',1,'ZZ Revenue','ZZ4000','Reversed'),
('ZZR1',2,'ZZ Units','ZZ7000','As Booked'),
('ZZR1',3,'ZZ Units','ZZ7100','As Booked');
INSERT INTO epm_gold.gold_scenario_trial_balance (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, amount) VALUES
('ZZSC','ZZE1',2026,3,'ZZ4000','ZZP1',-120),
('ZZSC','ZZE1',2026,3,'ZZ4000','ZZP2',-300),
('ZZSC','ZZE1',2026,3,'ZZ7000','ZZP1',10),
('ZZSC','ZZE1',2026,3,'ZZ7100','ZZP1',5),
('ZZSC','ZZE1',2026,3,'ZZ7100','ZZP1',3),
('ZZSC','ZZE1',2026,3,'ZZ7000','ZZP2',0);
INSERT INTO epm_staging.cost_allocation_run_weights (parent, idx, step, sender_member, receiver_member, driver, statistic, value_period, carried_forward, driver_value, source, effective_from) VALUES
('ZZR1',1,1,'ZZIT','ZZP1','ZZ Revenue','',3,0,100,'Account Set','1970-01-01'),
('ZZR1',2,1,'ZZIT','ZZP2','ZZ Revenue','',3,0,300.00000001,'Account Set','1970-01-01'),
('ZZR1',3,2,'ZZHR','ZZP1','ZZ Units','',3,0,15,'Account Set','1970-01-01'),
('ZZR1',4,2,'ZZHR','ZZP2','ZZ Units','',3,0,0,'Account Set','1970-01-01'),
('ZZR1',5,2,'ZZHR','ZZP9','ZZ Units','',3,0,4,'Account Set','1970-01-01'),
('ZZR1',6,3,'ZZFI','ZZP1','ZZ Headcount','ZZ Headcount',3,0,999,'Uploaded Statistic','1970-01-01');
