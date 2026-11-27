-- konsol#269 2b-2 W4(b) clean fixture: coefficients of a Declared Rate origin are in DRIVER
-- UNITS, so its own hop closes against the step's total units, not 1. The rows are produced
-- by konsol's cost_allocation_model (coefficient_rows), not derived by hand.
-- Run ZZRT (Step-Down, the plan's worked example): ZZIT charges 50 per ticket, tickets ZZHR 5,
-- ZZSA 8, ZZOP 6: own hop pool 19 = the sum of the step's driver units in run_weights, receiver
-- coefficients 5, 8, 6. ZZHR (share) passes the 5 units it received on 5/8 : 3/8 (3.125, 1.875)
-- and relieves its own pool with pool 1 (.625, .375).
-- Run ZZRQ (Reciprocal): ZZIT rate 50 per ticket (ZZHR 5, ZZSA 8, ZZOP 6); ZZHR share by
-- headcount ZZFM 4, ZZSA 1; ZZFM share by area ZZHR 5, ZZIT 1, ZZSA 1, ZZOP 1. ZZHR and ZZFM
-- are the reciprocal pair; ZZFM also sends to ZZIT, a rate sender, where cost stops (no pass
-- rows at ZZIT for any origin). Origin ZZIT: own pool 19; its units circulate as pass hops at
-- ZZHR (pool 10) and ZZFM (pool 8). Every hop closes; own pools: ZZIT 19, ZZHR 1, ZZFM 1.
INSERT INTO epm_staging.cost_allocation_run_weights (parent, idx, step, sender_member, receiver_member, driver, statistic, value_period, carried_forward, driver_value, source, effective_from, basis, rate, rate_from) VALUES
('ZZRT',1,1,'ZZIT','ZZHR','ZZ Tickets','ZZ Tickets',1,0,5,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRT',2,1,'ZZIT','ZZSA','ZZ Tickets','ZZ Tickets',1,0,8,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRT',3,1,'ZZIT','ZZOP','ZZ Tickets','ZZ Tickets',1,0,6,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRT',4,2,'ZZHR','ZZSA','ZZ Headcount','ZZ Headcount',1,0,5,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01'),
('ZZRT',5,2,'ZZHR','ZZOP','ZZ Headcount','ZZ Headcount',1,0,3,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01'),
('ZZRQ',1,1,'ZZIT','ZZHR','ZZ Tickets','ZZ Tickets',1,0,5,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRQ',2,1,'ZZIT','ZZSA','ZZ Tickets','ZZ Tickets',1,0,8,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRQ',3,1,'ZZIT','ZZOP','ZZ Tickets','ZZ Tickets',1,0,6,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRQ',4,2,'ZZHR','ZZFM','ZZ Headcount','ZZ Headcount',1,0,4,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01'),
('ZZRQ',5,2,'ZZHR','ZZSA','ZZ Headcount','ZZ Headcount',1,0,1,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01'),
('ZZRQ',6,3,'ZZFM','ZZHR','ZZ Area','ZZ Area',1,0,5,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01'),
('ZZRQ',7,3,'ZZFM','ZZIT','ZZ Area','ZZ Area',1,0,1,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01'),
('ZZRQ',8,3,'ZZFM','ZZSA','ZZ Area','ZZ Area',1,0,1,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01'),
('ZZRQ',9,3,'ZZFM','ZZOP','ZZ Area','ZZ Area',1,0,1,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01');
INSERT INTO epm_staging.cost_allocation_coefficients (run, origin_member, step, sender_member, receiver_member, driver, hop_kind, pool_coefficient, coefficient) VALUES
('ZZRT','ZZIT',1,'ZZIT','ZZHR','ZZ Tickets','own',19.000000000000,5.000000000000),
('ZZRT','ZZIT',1,'ZZIT','ZZSA','ZZ Tickets','own',19.000000000000,8.000000000000),
('ZZRT','ZZIT',1,'ZZIT','ZZOP','ZZ Tickets','own',19.000000000000,6.000000000000),
('ZZRT','ZZIT',2,'ZZHR','ZZSA','ZZ Headcount','pass',5.000000000000,3.125000000000),
('ZZRT','ZZIT',2,'ZZHR','ZZOP','ZZ Headcount','pass',5.000000000000,1.875000000000),
('ZZRT','ZZHR',2,'ZZHR','ZZSA','ZZ Headcount','own',1.000000000000,0.625000000000),
('ZZRT','ZZHR',2,'ZZHR','ZZOP','ZZ Headcount','own',1.000000000000,0.375000000000),
('ZZRQ','ZZIT',1,'ZZIT','ZZHR','ZZ Tickets','own',19.000000000000,5.000000000000),
('ZZRQ','ZZIT',1,'ZZIT','ZZSA','ZZ Tickets','own',19.000000000000,8.000000000000),
('ZZRQ','ZZIT',1,'ZZIT','ZZOP','ZZ Tickets','own',19.000000000000,6.000000000000),
('ZZRQ','ZZIT',2,'ZZHR','ZZFM','ZZ Headcount','pass',10.000000000000,8.000000000000),
('ZZRQ','ZZIT',2,'ZZHR','ZZSA','ZZ Headcount','pass',10.000000000000,2.000000000000),
('ZZRQ','ZZIT',3,'ZZFM','ZZHR','ZZ Area','pass',8.000000000000,5.000000000000),
('ZZRQ','ZZIT',3,'ZZFM','ZZIT','ZZ Area','pass',8.000000000000,1.000000000000),
('ZZRQ','ZZIT',3,'ZZFM','ZZSA','ZZ Area','pass',8.000000000000,1.000000000000),
('ZZRQ','ZZIT',3,'ZZFM','ZZOP','ZZ Area','pass',8.000000000000,1.000000000000),
('ZZRQ','ZZHR',2,'ZZHR','ZZFM','ZZ Headcount','own',1.000000000000,0.800000000000),
('ZZRQ','ZZHR',2,'ZZHR','ZZSA','ZZ Headcount','own',1.000000000000,0.200000000000),
('ZZRQ','ZZHR',2,'ZZHR','ZZFM','ZZ Headcount','pass',1.000000000000,0.800000000000),
('ZZRQ','ZZHR',2,'ZZHR','ZZSA','ZZ Headcount','pass',1.000000000000,0.200000000000),
('ZZRQ','ZZHR',3,'ZZFM','ZZHR','ZZ Area','pass',1.600000000000,1.000000000000),
('ZZRQ','ZZHR',3,'ZZFM','ZZIT','ZZ Area','pass',1.600000000000,0.200000000000),
('ZZRQ','ZZHR',3,'ZZFM','ZZSA','ZZ Area','pass',1.600000000000,0.200000000000),
('ZZRQ','ZZHR',3,'ZZFM','ZZOP','ZZ Area','pass',1.600000000000,0.200000000000),
('ZZRQ','ZZFM',2,'ZZHR','ZZFM','ZZ Headcount','pass',1.250000000000,1.000000000000),
('ZZRQ','ZZFM',2,'ZZHR','ZZSA','ZZ Headcount','pass',1.250000000000,0.250000000000),
('ZZRQ','ZZFM',3,'ZZFM','ZZHR','ZZ Area','own',1.000000000000,0.625000000000),
('ZZRQ','ZZFM',3,'ZZFM','ZZIT','ZZ Area','own',1.000000000000,0.125000000000),
('ZZRQ','ZZFM',3,'ZZFM','ZZSA','ZZ Area','own',1.000000000000,0.125000000000),
('ZZRQ','ZZFM',3,'ZZFM','ZZOP','ZZ Area','own',1.000000000000,0.125000000000),
('ZZRQ','ZZFM',3,'ZZFM','ZZHR','ZZ Area','pass',1.000000000000,0.625000000000),
('ZZRQ','ZZFM',3,'ZZFM','ZZIT','ZZ Area','pass',1.000000000000,0.125000000000),
('ZZRQ','ZZFM',3,'ZZFM','ZZSA','ZZ Area','pass',1.000000000000,0.125000000000),
('ZZRQ','ZZFM',3,'ZZFM','ZZOP','ZZ Area','pass',1.000000000000,0.125000000000);
