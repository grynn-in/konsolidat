-- gate: expect assert_cost_allocation_weight_source_valid flag 10
-- konsol#269 phase 2b-1 W2(b) must-flag fixture. Run ZZR1 is period 3; fourteen weight rows, ten wrong.
-- idx 1 ok: 'Uploaded Statistic', cites a statistic at the run period.
-- idx 2 ok: '' (pre-2b sync) carried from period 2: '' reads as a statistic row, and with idx 1
--   it is ONE source for ZZ Headcount, not two.
-- idx 3 ok: 'Fixed Weights' with its window start. idx 4 ok: 'Account Set' backed by a driver_accounts row.
-- idx 5 flagged: source 'Spreadsheet' is none of the three (nor '').
-- idx 6 flagged: a Fixed Weights row that cites a statistic.
-- idx 7 flagged: a Fixed Weights row carried forward.
-- idx 8 flagged: a Fixed Weights row read at period 2, not the run's period 3.
-- idx 9 flagged: a Fixed Weights row with effective_from unset (1970-01-01).
-- idx 10 flagged: an Account Set row (ZZ Area) with no driver_accounts row in the run.
-- idx 11 and 12 flagged: driver ZZ Mixed appears once as Fixed Weights and once as Account Set
--   in the same run; each row is otherwise well formed.
-- idx 13 flagged: an Uploaded Statistic row with a window start; only Fixed Weights carries one.
-- idx 14 flagged: an Account Set row (ZZ Signless) whose driver_accounts row has value_sign 'Absolute'.
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZR1','ZZRS1','Step-Down','dim_cost_center','Sender''s Own Accounts','','Follow Latest Data','ZZE1','ZZSC',2026,3);
INSERT INTO epm_staging.cost_allocation_run_driver_accounts (parent, idx, driver, main_account, declared_account, value_sign) VALUES
('ZZR1',1,'ZZ Revenue','ZZ4000','ZZ4000','Reversed'),
('ZZR1',2,'ZZ Mixed','ZZ7000','ZZ7000','As Booked'),
('ZZR1',3,'ZZ Signless','ZZ7200','ZZ7200','Absolute');
INSERT INTO epm_staging.cost_allocation_run_weights (parent, idx, step, sender_member, receiver_member, driver, statistic, value_period, carried_forward, driver_value, source, effective_from) VALUES
('ZZR1',1,1,'ZZIT','ZZP1','ZZ Headcount','ZZ Headcount',3,0,10,'Uploaded Statistic','1970-01-01'),
('ZZR1',2,1,'ZZIT','ZZP2','ZZ Headcount','ZZ Headcount',2,1,28,'','1970-01-01'),
('ZZR1',3,2,'ZZHR','ZZP1','ZZ Floor Area','',3,0,7,'Fixed Weights','2026-01-01'),
('ZZR1',4,3,'ZZFI','ZZP2','ZZ Revenue','',3,0,123,'Account Set','1970-01-01'),
('ZZR1',5,4,'ZZOP','ZZP1','ZZ Odd','',3,0,1,'Spreadsheet','1970-01-01'),
('ZZR1',6,2,'ZZHR','ZZP2','ZZ Floor Area','ZZ Headcount',3,0,3,'Fixed Weights','2026-01-01'),
('ZZR1',7,2,'ZZHR','ZZP3','ZZ Floor Area','',2,1,3,'Fixed Weights','2026-01-01'),
('ZZR1',8,2,'ZZHR','ZZP4','ZZ Floor Area','',2,0,3,'Fixed Weights','2026-01-01'),
('ZZR1',9,2,'ZZHR','ZZP5','ZZ Floor Area','',3,0,3,'Fixed Weights','1970-01-01'),
('ZZR1',10,5,'ZZMK','ZZP1','ZZ Area','',3,0,40,'Account Set','1970-01-01'),
('ZZR1',11,6,'ZZLG','ZZP1','ZZ Mixed','',3,0,2,'Fixed Weights','2026-01-01'),
('ZZR1',12,6,'ZZLG','ZZP2','ZZ Mixed','',3,0,8,'Account Set','1970-01-01'),
('ZZR1',13,1,'ZZIT','ZZP3','ZZ Headcount','ZZ Headcount',3,0,12,'Uploaded Statistic','2026-01-01'),
('ZZR1',14,7,'ZZSV','ZZP1','ZZ Signless','',3,0,9,'Account Set','1970-01-01');
