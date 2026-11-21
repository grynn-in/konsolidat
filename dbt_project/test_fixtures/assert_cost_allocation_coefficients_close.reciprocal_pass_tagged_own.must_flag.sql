-- gate: expect assert_cost_allocation_coefficients_close flag 4
-- konsol#269 RC6 must-flag fixture: the Reciprocal worked example with every `pass` row tagged `own`.
-- coefficients_close judges the staging rows (no build). Expected 4 rows:
--   hop level, 2: origin ZZIT step 1 sender ZZIT now holds the rows of pool_coefficient 1 and .25 together (pool min != max,
--   coefficients sum 1.25 != 1), and origin ZZHR step 2 sender ZZHR likewise (1 and .25, sum 1.25);
--   own sum, 2: the `own` hops of origin ZZIT now sum to 1 + .625 = 1.625 and those of ZZHR to .5 + 1 = 1.5, not 1.
-- tables epm_staging.cost_allocation_coefficients
INSERT INTO epm_staging.cost_allocation_coefficients (run, origin_member, step, sender_member, receiver_member, driver, hop_kind, pool_coefficient, coefficient) VALUES
('ZZRX','ZZIT',1,'ZZIT','ZZHR','ZZ Tickets','own',1.000000000000,0.500000000000),
('ZZRX','ZZIT',1,'ZZIT','ZZSA','ZZ Tickets','own',1.000000000000,0.300000000000),
('ZZRX','ZZIT',1,'ZZIT','ZZOP','ZZ Tickets','own',1.000000000000,0.200000000000),
('ZZRX','ZZIT',1,'ZZIT','ZZHR','ZZ Tickets','own',0.250000000000,0.125000000000),
('ZZRX','ZZIT',1,'ZZIT','ZZSA','ZZ Tickets','own',0.250000000000,0.075000000000),
('ZZRX','ZZIT',1,'ZZIT','ZZOP','ZZ Tickets','own',0.250000000000,0.050000000000),
('ZZRX','ZZIT',2,'ZZHR','ZZIT','ZZ Headcount','own',0.625000000000,0.250000000000),
('ZZRX','ZZIT',2,'ZZHR','ZZSA','ZZ Headcount','own',0.625000000000,0.250000000000),
('ZZRX','ZZIT',2,'ZZHR','ZZOP','ZZ Headcount','own',0.625000000000,0.125000000000),
('ZZRX','ZZHR',1,'ZZIT','ZZHR','ZZ Tickets','own',0.500000000000,0.250000000000),
('ZZRX','ZZHR',1,'ZZIT','ZZSA','ZZ Tickets','own',0.500000000000,0.150000000000),
('ZZRX','ZZHR',1,'ZZIT','ZZOP','ZZ Tickets','own',0.500000000000,0.100000000000),
('ZZRX','ZZHR',2,'ZZHR','ZZIT','ZZ Headcount','own',1.000000000000,0.400000000000),
('ZZRX','ZZHR',2,'ZZHR','ZZSA','ZZ Headcount','own',1.000000000000,0.400000000000),
('ZZRX','ZZHR',2,'ZZHR','ZZOP','ZZ Headcount','own',1.000000000000,0.200000000000),
('ZZRX','ZZHR',2,'ZZHR','ZZIT','ZZ Headcount','own',0.250000000000,0.100000000000),
('ZZRX','ZZHR',2,'ZZHR','ZZSA','ZZ Headcount','own',0.250000000000,0.100000000000),
('ZZRX','ZZHR',2,'ZZHR','ZZOP','ZZ Headcount','own',0.250000000000,0.050000000000);
