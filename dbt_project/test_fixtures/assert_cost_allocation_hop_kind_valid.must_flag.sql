-- gate: expect assert_cost_allocation_hop_kind_valid flag 4
-- konsol#269 RF5 (review finding 6) must-flag fixture. hop_kind is `own` or `pass`; nothing else.
-- Coefficient rows: one blank and one 'xyz' (2 rows). Lines: one blank and one 'xyz' (2 rows).
-- The valid `own` and `pass` rows beside them must not flag.
-- tables epm_staging.cost_allocation_coefficients, epm_gold.gold_cost_allocation
INSERT INTO epm_staging.cost_allocation_coefficients (run, origin_member, step, sender_member, receiver_member, driver, hop_kind, pool_coefficient, coefficient) VALUES
('ZZRH','ZZIT',1,'ZZIT','ZZSA','ZZ Tickets','own',1.000000000000,0.600000000000),
('ZZRH','ZZIT',1,'ZZIT','ZZOP','ZZ Tickets','pass',1.000000000000,0.200000000000),
('ZZRH','ZZIT',1,'ZZIT','ZZHR','ZZ Tickets','',1.000000000000,0.100000000000),
('ZZRH','ZZIT',1,'ZZIT','ZZP1','ZZ Tickets','xyz',1.000000000000,0.100000000000);
INSERT INTO epm_gold.gold_cost_allocation (run, main_account, line_type, hop_kind, origin_member, step, sender_member, receiver_member, member, origin_amount, amount) VALUES
('ZZRH','ZZ6000','sent','own','ZZIT',1,'ZZIT','ZZSA','ZZIT',1000,-600),
('ZZRH','ZZ6000','received','own','ZZIT',1,'ZZIT','ZZSA','ZZSA',1000,600),
('ZZRH','ZZ6000','sent','pass','ZZIT',1,'ZZIT','ZZOP','ZZIT',1000,-200),
('ZZRH','ZZ6000','received','pass','ZZIT',1,'ZZIT','ZZOP','ZZOP',1000,200),
('ZZRH','ZZ6000','sent','','ZZIT',1,'ZZIT','ZZHR','ZZIT',1000,-100),
('ZZRH','ZZ6000','received','xyz','ZZIT',1,'ZZIT','ZZP1','ZZP1',1000,100);
