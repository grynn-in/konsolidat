-- konsol#269 2b-2 W7 clean fixture: a frozen absorption row whose pool still matches the trial balance.
-- ZZRF (Freeze at Approval, Declared Allocation Account ZZ6999, ZZE1 P1) was frozen with ZZIT, the rate
-- sender (50 per ticket, 19 tickets), at pool 1,000 on ZZ6000: charged 950, variance 50. The trial
-- balance still says 1,000, so nothing drifts. ZZHR (share sender, pool 400) is not a row of the
-- absorption model and is not judged here (assert_cost_allocation_frozen_drift covers its lines).
-- tables epm_gold.gold_scenario_trial_balance, epm_gold.gold_cost_allocation_absorption_frozen
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
INSERT INTO epm_gold.gold_scenario_trial_balance (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, amount) VALUES
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZIT',1000),
('ZZSC','ZZE1',2026,1,'ZZ6000','ZZHR',400);
INSERT INTO epm_gold.gold_cost_allocation_absorption_frozen (run, rule_set, method, scenario_id, data_area_id, fiscal_year, fiscal_period, allocation_dimension, allocation_account, sender_member, step, rate, units, pool, received, charged, variance, frozen_at) VALUES
('ZZRF','ZZRS1','Step-Down','ZZSC','ZZE1',2026,1,'dim_cost_center','ZZ6999','ZZIT',1,50,19,1000,0,950,50,'2026-11-01 10:00:00');
