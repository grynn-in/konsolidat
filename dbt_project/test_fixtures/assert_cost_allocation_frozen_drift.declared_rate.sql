-- konsol#269 2b-2 W4(d) clean fixture: a frozen run with a Declared Rate origin does not drift.
-- ZZRF (Freeze at Approval, Declared Allocation Account ZZ6999, ZZE1 P1) was frozen with ZZIT
-- charging 50 per ticket (19 tickets, relief 950 on ZZ6999) and ZZHR's pool 400 on ZZ6000.
-- ZZIT's frozen origin_amount is the RATE (50), not a pool, and its trial balance pool (1,000 on
-- ZZ6000) never enters its lines: the test leaves rate origins out on both sides, else it would
-- report 50 against 0 on ZZ6999 and 0 against 1,000 on ZZ6000. ZZHR: frozen 400, TB still 400.
-- tables epm_gold.gold_scenario_trial_balance, epm_gold.gold_cost_allocation_frozen
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZRF','ZZRS1','Step-Down','dim_cost_center','Declared Allocation Account','ZZ6999','Freeze at Approval','ZZE1','ZZSC',2026,1);
INSERT INTO epm_staging.cost_allocation_run_accounts (parent, idx, main_account, declared_account) VALUES
('ZZRF',1,'ZZ6000','');
INSERT INTO epm_staging.cost_allocation_run_weights (parent, idx, step, sender_member, receiver_member, driver, statistic, value_period, carried_forward, driver_value, source, effective_from, basis, rate, rate_from) VALUES
('ZZRF',1,1,'ZZIT','ZZHR','ZZ Tickets','ZZ Tickets',1,0,5,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRF',2,1,'ZZIT','ZZSA','ZZ Tickets','ZZ Tickets',1,0,8,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRF',3,1,'ZZIT','ZZOP','ZZ Tickets','ZZ Tickets',1,0,6,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRF',4,2,'ZZHR','ZZSA','ZZ Headcount','ZZ Headcount',1,0,5,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01'),
('ZZRF',5,2,'ZZHR','ZZOP','ZZ Headcount','ZZ Headcount',1,0,3,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01');
INSERT INTO epm_staging.cost_allocation_coefficients (run, origin_member, step, sender_member, receiver_member, driver, hop_kind, pool_coefficient, coefficient) VALUES
('ZZRF','ZZIT',1,'ZZIT','ZZHR','ZZ Tickets','own',19.000000000000,5.000000000000),
('ZZRF','ZZIT',1,'ZZIT','ZZSA','ZZ Tickets','own',19.000000000000,8.000000000000),
('ZZRF','ZZIT',1,'ZZIT','ZZOP','ZZ Tickets','own',19.000000000000,6.000000000000),
('ZZRF','ZZIT',2,'ZZHR','ZZSA','ZZ Headcount','pass',5.000000000000,3.125000000000),
('ZZRF','ZZIT',2,'ZZHR','ZZOP','ZZ Headcount','pass',5.000000000000,1.875000000000),
('ZZRF','ZZHR',2,'ZZHR','ZZSA','ZZ Headcount','own',1.000000000000,0.625000000000),
('ZZRF','ZZHR',2,'ZZHR','ZZOP','ZZ Headcount','own',1.000000000000,0.375000000000);
INSERT INTO epm_gold.gold_scenario_trial_balance (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, amount) VALUES
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZIT',1000),
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZHR',400);
INSERT INTO epm_gold.gold_cost_allocation_frozen (run, rule_set, method, scenario_id, data_area_id, main_account, pool_account, allocation_dimension, member, line_type, hop_kind, basis, origin_member, sender_member, receiver_member, driver, fiscal_year, fiscal_period, step, coefficient, origin_amount, amount, frozen_at) VALUES
('ZZRF','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6999','ZZ6999','dim_cost_center','ZZIT','sent','own','Declared Rate','ZZIT','ZZIT','ZZHR','ZZ Tickets',2026,1,1,5,50,-250,'2026-11-01 10:00:00'),
('ZZRF','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6999','ZZ6999','dim_cost_center','ZZHR','received','own','Declared Rate','ZZIT','ZZIT','ZZHR','ZZ Tickets',2026,1,1,5,50,250,'2026-11-01 10:00:00'),
('ZZRF','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6999','ZZ6999','dim_cost_center','ZZIT','sent','own','Declared Rate','ZZIT','ZZIT','ZZSA','ZZ Tickets',2026,1,1,8,50,-400,'2026-11-01 10:00:00'),
('ZZRF','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6999','ZZ6999','dim_cost_center','ZZSA','received','own','Declared Rate','ZZIT','ZZIT','ZZSA','ZZ Tickets',2026,1,1,8,50,400,'2026-11-01 10:00:00'),
('ZZRF','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6999','ZZ6999','dim_cost_center','ZZIT','sent','own','Declared Rate','ZZIT','ZZIT','ZZOP','ZZ Tickets',2026,1,1,6,50,-300,'2026-11-01 10:00:00'),
('ZZRF','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6999','ZZ6999','dim_cost_center','ZZOP','received','own','Declared Rate','ZZIT','ZZIT','ZZOP','ZZ Tickets',2026,1,1,6,50,300,'2026-11-01 10:00:00'),
('ZZRF','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6999','ZZ6999','dim_cost_center','ZZHR','sent','pass','Declared Rate','ZZIT','ZZHR','ZZSA','ZZ Headcount',2026,1,2,3.125,50,-156.25,'2026-11-01 10:00:00'),
('ZZRF','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6999','ZZ6999','dim_cost_center','ZZSA','received','pass','Declared Rate','ZZIT','ZZHR','ZZSA','ZZ Headcount',2026,1,2,3.125,50,156.25,'2026-11-01 10:00:00'),
('ZZRF','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6999','ZZ6999','dim_cost_center','ZZHR','sent','pass','Declared Rate','ZZIT','ZZHR','ZZOP','ZZ Headcount',2026,1,2,1.875,50,-93.75,'2026-11-01 10:00:00'),
('ZZRF','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6999','ZZ6999','dim_cost_center','ZZOP','received','pass','Declared Rate','ZZIT','ZZHR','ZZOP','ZZ Headcount',2026,1,2,1.875,50,93.75,'2026-11-01 10:00:00'),
('ZZRF','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6000','ZZ6000','dim_cost_center','ZZHR','sent','own','Share of Pool','ZZHR','ZZHR','ZZSA','ZZ Headcount',2026,1,2,0.625,400,-250,'2026-11-01 10:00:00'),
('ZZRF','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6999','ZZ6000','dim_cost_center','ZZSA','received','own','Share of Pool','ZZHR','ZZHR','ZZSA','ZZ Headcount',2026,1,2,0.625,400,250,'2026-11-01 10:00:00'),
('ZZRF','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6000','ZZ6000','dim_cost_center','ZZHR','sent','own','Share of Pool','ZZHR','ZZHR','ZZOP','ZZ Headcount',2026,1,2,0.375,400,-150,'2026-11-01 10:00:00'),
('ZZRF','ZZRS1','Step-Down','ZZSC','ZZE1','ZZ6999','ZZ6000','dim_cost_center','ZZOP','received','own','Share of Pool','ZZHR','ZZHR','ZZOP','ZZ Headcount',2026,1,2,0.375,400,150,'2026-11-01 10:00:00');
