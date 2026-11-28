-- konsol#269 2b-2 W5 clean fixture: every line's basis is the one its origin's weight rows declare.
-- Run ZZRT (the rate worked example): origin ZZIT's weight rows say 'Declared Rate' at 50, so its lines
-- carry basis 'Declared Rate' and origin_amount 50 (the rate); origin ZZHR's rows say 'Share of Pool',
-- so its lines carry 'Share of Pool' and origin_amount 400 (its pool).
-- Run ZZRP was synced before 2b-2: its weight rows carry basis '' (read as Share of Pool) and its
-- lines 'Share of Pool' (the frozen table's column default and what the macro writes).
-- tables epm_gold.gold_cost_allocation, epm_staging.cost_allocation_run_weights
INSERT INTO epm_staging.cost_allocation_run_weights (parent, idx, step, sender_member, receiver_member, driver, statistic, value_period, carried_forward, driver_value, source, effective_from, basis, rate, rate_from) VALUES
('ZZRT',1,1,'ZZIT','ZZHR','ZZ Tickets','ZZ Tickets',1,0,5,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRT',2,1,'ZZIT','ZZSA','ZZ Tickets','ZZ Tickets',1,0,8,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRT',3,1,'ZZIT','ZZOP','ZZ Tickets','ZZ Tickets',1,0,6,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRT',4,2,'ZZHR','ZZSA','ZZ Headcount','ZZ Headcount',1,0,5,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01'),
('ZZRT',5,2,'ZZHR','ZZOP','ZZ Headcount','ZZ Headcount',1,0,3,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01'),
('ZZRP',1,1,'ZZIT','ZZP1','ZZHC','ZZHC',1,0,10,'','1970-01-01','',0,'1970-01-01');
INSERT INTO epm_gold.gold_cost_allocation (run, main_account, pool_account, line_type, hop_kind, basis, origin_member, step, sender_member, receiver_member, member, origin_amount, amount) VALUES
('ZZRT','ZZ6999','ZZ6999','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZHR','ZZIT',50,-250),
('ZZRT','ZZ6999','ZZ6999','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZHR','ZZHR',50,250),
('ZZRT','ZZ6999','ZZ6999','sent','pass','Declared Rate','ZZIT',2,'ZZHR','ZZSA','ZZHR',50,-156.25),
('ZZRT','ZZ6999','ZZ6999','received','pass','Declared Rate','ZZIT',2,'ZZHR','ZZSA','ZZSA',50,156.25),
('ZZRT','ZZ6000','ZZ6000','sent','own','Share of Pool','ZZHR',2,'ZZHR','ZZSA','ZZHR',400,-250),
('ZZRT','ZZ6999','ZZ6000','received','own','Share of Pool','ZZHR',2,'ZZHR','ZZSA','ZZSA',400,250),
('ZZRP','ZZ6000','ZZ6000','sent','own','Share of Pool','ZZIT',1,'ZZIT','ZZP1','ZZIT',1000,-1000),
('ZZRP','ZZ6000','ZZ6000','received','own','Share of Pool','ZZIT',1,'ZZIT','ZZP1','ZZP1',1000,1000);
