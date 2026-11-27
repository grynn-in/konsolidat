-- konsol#269 phase 2b-1 W2(a) clean fixture: only statistic rows are held to a statistic.
-- Run ZZR1 is period 3. idx 1 cites ZZ Headcount at period 3 (source 'Uploaded Statistic');
-- idx 2 is the same row as a pre-2b sync wrote it (source '' means statistic).
-- idx 3 is a Fixed Weights row and idx 4 an Account Set row: blank statistic, no
-- statistic value anywhere equals their driver_value (7 and 123), and the test must
-- not ask one of them. Before W2(a) both rows flagged (the test required every row to
-- match a statistic), so this fixture fails on the unchanged test.
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZR1','ZZRS1','Direct','dim_cost_center','Sender''s Own Accounts','','Follow Latest Data','ZZE1','ZZSC',2026,3);
INSERT INTO epm_staging.cost_allocation_statistics (name, driver, dimension, data_area_id, scenario_id, fiscal_year) VALUES
('ZZ Headcount','ZZ Headcount','dim_cost_center','ZZE1','ZZSC',2026);
INSERT INTO epm_staging.cost_allocation_statistic_values (parent, idx, fiscal_period, member, value) VALUES
('ZZ Headcount',1,3,'ZZP1',10),
('ZZ Headcount',2,3,'ZZP2',30);
INSERT INTO epm_staging.cost_allocation_run_driver_accounts (parent, idx, driver, main_account, value_sign) VALUES
('ZZR1',1,'ZZ Revenue','ZZ4000','Reversed');
INSERT INTO epm_staging.cost_allocation_run_weights (parent, idx, step, sender_member, receiver_member, driver, statistic, value_period, carried_forward, driver_value, source, effective_from) VALUES
('ZZR1',1,1,'ZZIT','ZZP1','ZZ Headcount','ZZ Headcount',3,0,10,'Uploaded Statistic','1970-01-01'),
('ZZR1',2,1,'ZZIT','ZZP2','ZZ Headcount','ZZ Headcount',3,0,30,'','1970-01-01'),
('ZZR1',3,2,'ZZHR','ZZP1','ZZ Floor Area','',3,0,7,'Fixed Weights','2026-01-01'),
('ZZR1',4,2,'ZZHR','ZZP2','ZZ Revenue','',3,0,123,'Account Set','1970-01-01');
