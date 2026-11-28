-- gate: expect assert_cost_allocation_amounts flag 1
-- konsol#269 2b-2 W4(d) must-flag fixture: the share origin of a live rate run is stale, the rate
-- origin is not judged. Same seed as the clean fixture, but the TB says ZZHR 450 and the published
-- lines still carry 400: one row, ZZRL / ZZ6000 / ZZHR. ZZIT (rate 50 published; TB pool 1,000)
-- is not a row.
-- tables epm_gold.gold_cost_allocation, epm_gold.gold_scenario_trial_balance
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZRL','ZZRS1','Step-Down','dim_cost_center','Declared Allocation Account','ZZ6999','Follow Latest Data','ZZE1','ZZSC',2026,1);
INSERT INTO epm_staging.cost_allocation_run_accounts (parent, idx, main_account, declared_account) VALUES
('ZZRL',1,'ZZ6000','');
INSERT INTO epm_staging.cost_allocation_run_weights (parent, idx, step, sender_member, receiver_member, driver, statistic, value_period, carried_forward, driver_value, source, effective_from, basis, rate, rate_from) VALUES
('ZZRL',1,1,'ZZIT','ZZHR','ZZ Tickets','ZZ Tickets',1,0,5,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRL',2,1,'ZZIT','ZZSA','ZZ Tickets','ZZ Tickets',1,0,8,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRL',3,1,'ZZIT','ZZOP','ZZ Tickets','ZZ Tickets',1,0,6,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRL',4,2,'ZZHR','ZZSA','ZZ Headcount','ZZ Headcount',1,0,5,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01'),
('ZZRL',5,2,'ZZHR','ZZOP','ZZ Headcount','ZZ Headcount',1,0,3,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01');
INSERT INTO epm_gold.gold_scenario_trial_balance (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, amount) VALUES
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZIT',1000),
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZHR',450);
INSERT INTO epm_gold.gold_cost_allocation (run, main_account, pool_account, line_type, hop_kind, basis, origin_member, step, sender_member, receiver_member, member, origin_amount, amount) VALUES
('ZZRL','ZZ6999','ZZ6999','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZHR','ZZIT',50,-250),
('ZZRL','ZZ6999','ZZ6999','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZHR','ZZHR',50,250),
('ZZRL','ZZ6999','ZZ6999','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZSA','ZZIT',50,-400),
('ZZRL','ZZ6999','ZZ6999','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZSA','ZZSA',50,400),
('ZZRL','ZZ6999','ZZ6999','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZOP','ZZIT',50,-300),
('ZZRL','ZZ6999','ZZ6999','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZOP','ZZOP',50,300),
('ZZRL','ZZ6999','ZZ6999','sent','pass','Declared Rate','ZZIT',2,'ZZHR','ZZSA','ZZHR',50,-156.25),
('ZZRL','ZZ6999','ZZ6999','received','pass','Declared Rate','ZZIT',2,'ZZHR','ZZSA','ZZSA',50,156.25),
('ZZRL','ZZ6999','ZZ6999','sent','pass','Declared Rate','ZZIT',2,'ZZHR','ZZOP','ZZHR',50,-93.75),
('ZZRL','ZZ6999','ZZ6999','received','pass','Declared Rate','ZZIT',2,'ZZHR','ZZOP','ZZOP',50,93.75),
('ZZRL','ZZ6000','ZZ6000','sent','own','Share of Pool','ZZHR',2,'ZZHR','ZZSA','ZZHR',400,-250),
('ZZRL','ZZ6999','ZZ6000','received','own','Share of Pool','ZZHR',2,'ZZHR','ZZSA','ZZSA',400,250),
('ZZRL','ZZ6000','ZZ6000','sent','own','Share of Pool','ZZHR',2,'ZZHR','ZZOP','ZZHR',400,-150),
('ZZRL','ZZ6999','ZZ6000','received','own','Share of Pool','ZZHR',2,'ZZHR','ZZOP','ZZOP',400,150);
