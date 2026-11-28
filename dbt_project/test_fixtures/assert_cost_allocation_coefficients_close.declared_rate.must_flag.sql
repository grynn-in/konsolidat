-- gate: expect assert_cost_allocation_coefficients_close flag 2
-- konsol#269 2b-2 W4(b) must-flag fixture: a Declared Rate origin's own hop must close against
-- the step's total driver units in run_weights. Two rate origins do not; every hop itself closes.
-- ZZR1 origin ZZIT: own pool 19 (5 + 8 + 6) but the weights say 20 units (ZZHR 6, ZZSA 8,
--   ZZOP 6): the coefficients were not rebuilt after a weight changed. One row.
-- ZZR2 origin ZZIT: built by the SHARE rule (pool 1, coefficients 5/19, 8/19, 6/19) although the
--   step charges a rate; its units sum to 19. One row.
-- ZZR1 origin ZZHR is a share origin with own pool 1 and no rate rows: not flagged.
INSERT INTO epm_staging.cost_allocation_run_weights (parent, idx, step, sender_member, receiver_member, driver, statistic, value_period, carried_forward, driver_value, source, effective_from, basis, rate, rate_from) VALUES
('ZZR1',1,1,'ZZIT','ZZHR','ZZ Tickets','ZZ Tickets',1,0,6,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZR1',2,1,'ZZIT','ZZSA','ZZ Tickets','ZZ Tickets',1,0,8,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZR1',3,1,'ZZIT','ZZOP','ZZ Tickets','ZZ Tickets',1,0,6,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZR1',4,2,'ZZHR','ZZSA','ZZ Headcount','ZZ Headcount',1,0,5,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01'),
('ZZR1',5,2,'ZZHR','ZZOP','ZZ Headcount','ZZ Headcount',1,0,3,'Uploaded Statistic','1970-01-01','Share of Pool',0,'1970-01-01'),
('ZZR2',1,1,'ZZIT','ZZHR','ZZ Tickets','ZZ Tickets',1,0,5,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZR2',2,1,'ZZIT','ZZSA','ZZ Tickets','ZZ Tickets',1,0,8,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZR2',3,1,'ZZIT','ZZOP','ZZ Tickets','ZZ Tickets',1,0,6,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01');
INSERT INTO epm_staging.cost_allocation_coefficients (run, origin_member, step, sender_member, receiver_member, driver, hop_kind, pool_coefficient, coefficient) VALUES
('ZZR1','ZZIT',1,'ZZIT','ZZHR','ZZ Tickets','own',19.000000000000,5.000000000000),
('ZZR1','ZZIT',1,'ZZIT','ZZSA','ZZ Tickets','own',19.000000000000,8.000000000000),
('ZZR1','ZZIT',1,'ZZIT','ZZOP','ZZ Tickets','own',19.000000000000,6.000000000000),
('ZZR1','ZZIT',2,'ZZHR','ZZSA','ZZ Headcount','pass',5.000000000000,3.125000000000),
('ZZR1','ZZIT',2,'ZZHR','ZZOP','ZZ Headcount','pass',5.000000000000,1.875000000000),
('ZZR1','ZZHR',2,'ZZHR','ZZSA','ZZ Headcount','own',1.000000000000,0.625000000000),
('ZZR1','ZZHR',2,'ZZHR','ZZOP','ZZ Headcount','own',1.000000000000,0.375000000000),
('ZZR2','ZZIT',1,'ZZIT','ZZHR','ZZ Tickets','own',1.000000000000,0.263157894737),
('ZZR2','ZZIT',1,'ZZIT','ZZSA','ZZ Tickets','own',1.000000000000,0.421052631579),
('ZZR2','ZZIT',1,'ZZIT','ZZOP','ZZ Tickets','own',1.000000000000,0.315789473684);
