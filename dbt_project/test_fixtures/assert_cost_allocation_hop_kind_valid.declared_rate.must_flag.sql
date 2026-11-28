-- gate: expect assert_cost_allocation_hop_kind_valid flag 3
-- konsol#269 2b-2 W4(e) must-flag fixture: a Declared Rate sender is a SINK, it never passes cost on.
-- Run ZZRT: ZZIT charges a rate (weight rows 'Declared Rate'). Three rows:
--   coefficient: a `pass` hop at sender ZZIT for origin ZZHR (ZZIT passing on the 80 it received);
--   line (2): both lines of a `pass` hop sent by ZZIT for origin ZZIT (its own returning ticket passed
--   on again): the sent line at ZZIT and the received line at ZZSA, one row each like any bad line.
-- Every hop_kind here is 'own' or 'pass', so the shape check adds nothing; ZZHR's pass rows are fine.
-- tables epm_staging.cost_allocation_coefficients, epm_staging.cost_allocation_run_weights, epm_gold.gold_cost_allocation
INSERT INTO epm_staging.cost_allocation_run_weights (parent, idx, step, sender_member, receiver_member, driver, statistic, value_period, carried_forward, driver_value, source, effective_from, basis, rate, rate_from) VALUES
('ZZRT',1,1,'ZZIT','ZZHR','ZZ Tickets','ZZ Tickets',1,0,5,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRT',2,1,'ZZIT','ZZSA','ZZ Tickets','ZZ Tickets',1,0,8,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRT',3,2,'ZZHR','ZZIT','ZZ Headcount','ZZ Headcount',1,0,1,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01'),
('ZZRT',4,2,'ZZHR','ZZSA','ZZ Headcount','ZZ Headcount',1,0,4,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01');
INSERT INTO epm_staging.cost_allocation_coefficients (run, origin_member, step, sender_member, receiver_member, driver, hop_kind, pool_coefficient, coefficient) VALUES
('ZZRT','ZZIT',1,'ZZIT','ZZHR','ZZ Tickets','own',13.000000000000,5.000000000000),
('ZZRT','ZZIT',1,'ZZIT','ZZSA','ZZ Tickets','own',13.000000000000,8.000000000000),
('ZZRT','ZZIT',2,'ZZHR','ZZIT','ZZ Headcount','pass',5.000000000000,1.000000000000),
('ZZRT','ZZIT',2,'ZZHR','ZZSA','ZZ Headcount','pass',5.000000000000,4.000000000000),
('ZZRT','ZZHR',2,'ZZHR','ZZIT','ZZ Headcount','own',1.000000000000,0.200000000000),
('ZZRT','ZZHR',2,'ZZHR','ZZSA','ZZ Headcount','own',1.000000000000,0.800000000000),
('ZZRT','ZZHR',1,'ZZIT','ZZSA','ZZ Tickets','pass',0.200000000000,0.200000000000);
INSERT INTO epm_gold.gold_cost_allocation (run, main_account, pool_account, line_type, hop_kind, basis, origin_member, step, sender_member, receiver_member, member, origin_amount, amount) VALUES
('ZZRT','ZZ6999','ZZ6999','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZHR','ZZIT',50,-250),
('ZZRT','ZZ6999','ZZ6999','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZHR','ZZHR',50,250),
('ZZRT','ZZ6999','ZZ6999','sent','pass','Declared Rate','ZZIT',2,'ZZHR','ZZIT','ZZHR',50,-50),
('ZZRT','ZZ6999','ZZ6999','received','pass','Declared Rate','ZZIT',2,'ZZHR','ZZIT','ZZIT',50,50),
('ZZRT','ZZ6999','ZZ6999','sent','pass','Declared Rate','ZZIT',1,'ZZIT','ZZSA','ZZIT',50,-50),
('ZZRT','ZZ6999','ZZ6999','received','pass','Declared Rate','ZZIT',1,'ZZIT','ZZSA','ZZSA',50,50);
