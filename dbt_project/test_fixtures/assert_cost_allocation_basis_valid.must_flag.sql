-- gate: expect assert_cost_allocation_basis_valid flag 4
-- konsol#269 2b-2 W5 must-flag fixture. Four rows:
--   weight ZZRA / ZZIT step 1: a Declared Rate step whose rows disagree on the rate (50, 50, 55);
--   weight ZZRB / ZZHR step 2: basis 'Rate' is neither Share of Pool nor Declared Rate;
--   line ZZRA / ZZHR: carries basis 'Declared Rate' although ZZHR's weight rows say Share of Pool;
--   line ZZRA / ZZHR: that same line's origin_amount (400, its pool) is not a declared rate of the run.
-- ZZRA / ZZIT's lines (basis 'Declared Rate', origin_amount 50) match a rate the step declares and are
-- not rows, nor is run ZZRC, a plain share run.
-- tables epm_gold.gold_cost_allocation, epm_staging.cost_allocation_run_weights
INSERT INTO epm_staging.cost_allocation_run_weights (parent, idx, step, sender_member, receiver_member, driver, statistic, value_period, carried_forward, driver_value, source, effective_from, basis, rate, rate_from) VALUES
('ZZRA',1,1,'ZZIT','ZZHR','ZZ Tickets','ZZ Tickets',1,0,5,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRA',2,1,'ZZIT','ZZSA','ZZ Tickets','ZZ Tickets',1,0,8,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRA',3,1,'ZZIT','ZZOP','ZZ Tickets','ZZ Tickets',1,0,6,'Uploaded Statistic','1970-01-01','Declared Rate',55,'2026-01-01'),
('ZZRA',4,2,'ZZHR','ZZSA','ZZ Headcount','ZZ Headcount',1,0,5,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01'),
('ZZRA',5,2,'ZZHR','ZZOP','ZZ Headcount','ZZ Headcount',1,0,3,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01'),
('ZZRB',1,2,'ZZHR','ZZSA','ZZ Headcount','ZZ Headcount',1,0,5,'Uploaded Statistic','1970-01-01','Rate',0,'1970-01-01'),
('ZZRC',1,1,'ZZIT','ZZP1','ZZHC','ZZHC',1,0,10,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01');
INSERT INTO epm_gold.gold_cost_allocation (run, main_account, pool_account, line_type, hop_kind, basis, origin_member, step, sender_member, receiver_member, member, origin_amount, amount) VALUES
('ZZRA','ZZ6999','ZZ6999','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZHR','ZZIT',50,-250),
('ZZRA','ZZ6999','ZZ6999','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZHR','ZZHR',50,250),
('ZZRA','ZZ6000','ZZ6000','sent','own','Declared Rate','ZZHR',2,'ZZHR','ZZSA','ZZHR',400,-250),
('ZZRA','ZZ6999','ZZ6000','received','own','Declared Rate','ZZHR',2,'ZZHR','ZZSA','ZZSA',400,250),
('ZZRC','ZZ6000','ZZ6000','sent','own','Share of Pool','ZZIT',1,'ZZIT','ZZP1','ZZIT',1000,-1000),
('ZZRC','ZZ6000','ZZ6000','received','own','Share of Pool','ZZIT',1,'ZZIT','ZZP1','ZZP1',1000,1000);
