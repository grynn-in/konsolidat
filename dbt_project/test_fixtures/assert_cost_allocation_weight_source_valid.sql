-- konsol#269 phase 2b-1 W2(b) clean fixture: every weight row has the shape its source declares.
-- Run ZZR1 is period 3 (ZZE1, ZZSC, 2026).
-- idx 1 'Uploaded Statistic' cites a statistic, read at the run period, not carried.
-- idx 2 '' (a pre-2b sync) is the same row carried from period 2: '' is read as a statistic row.
-- idx 3 'Fixed Weights': blank statistic, not carried, run period, window start set.
-- idx 4 'Account Set': blank statistic, not carried, run period, effective_from unset
--   (1970-01-01), and the run holds a driver_accounts row for ZZ Revenue with a valid sign.
-- idx 5 'Account Set' for a second driver (ZZ Units) read As Booked from two accounts.
-- Every driver has one source in the run.
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZR1','ZZRS1','Step-Down','dim_cost_center','Sender''s Own Accounts','','Follow Latest Data','ZZE1','ZZSC',2026,3);
INSERT INTO epm_staging.cost_allocation_run_driver_accounts (parent, idx, driver, main_account, value_sign) VALUES
('ZZR1',1,'ZZ Revenue','ZZ4000','Reversed'),
('ZZR1',2,'ZZ Units','ZZ7000','As Booked'),
('ZZR1',3,'ZZ Units','ZZ7100','As Booked');
INSERT INTO epm_staging.cost_allocation_run_weights (parent, idx, step, sender_member, receiver_member, driver, statistic, value_period, carried_forward, driver_value, source, effective_from) VALUES
('ZZR1',1,1,'ZZIT','ZZP1','ZZ Headcount','ZZ Headcount',3,0,10,'Uploaded Statistic','1970-01-01'),
('ZZR1',2,1,'ZZIT','ZZP2','ZZ Headcount','ZZ Headcount',2,1,28,'','1970-01-01'),
('ZZR1',3,2,'ZZHR','ZZP1','ZZ Floor Area','',3,0,7,'Fixed Weights','2026-01-01'),
('ZZR1',4,3,'ZZFI','ZZP2','ZZ Revenue','',3,0,123,'Account Set','1970-01-01'),
('ZZR1',5,4,'ZZOP','ZZP1','ZZ Units','',3,0,15,'Account Set','1970-01-01');
