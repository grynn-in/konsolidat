-- gate: expect assert_cost_allocation_coefficients_close flag 2
-- konsol#269 W2 (T5) must-flag fixture, two hops that do not close.
-- Origin ZZIT step 2 sender ZZHR: receivers sum to .19 against a pool of .2.
-- Origin ZZHR step 2 sender ZZHR: receivers sum to 1.000000000001 against 1.
-- Origin ZZIT step 1 closes and is not flagged.
-- tables epm_staging.cost_allocation_coefficients
CREATE TABLE IF NOT EXISTS epm_staging.cost_allocation_coefficients (run String, origin_member String, step UInt16, sender_member String, receiver_member String, driver String, pool_coefficient Decimal(38,12), coefficient Decimal(38,12)) ENGINE = MergeTree ORDER BY (run, origin_member, step, receiver_member);
INSERT INTO epm_staging.cost_allocation_coefficients (run, origin_member, step, sender_member, receiver_member, driver, pool_coefficient, coefficient) VALUES
('ZZR1','ZZIT',1,'ZZIT','ZZHR','ZZ Headcount',1,0.2),
('ZZR1','ZZIT',1,'ZZIT','ZZP1','ZZ Headcount',1,0.5),
('ZZR1','ZZIT',1,'ZZIT','ZZP2','ZZ Headcount',1,0.3),
('ZZR1','ZZIT',2,'ZZHR','ZZP1','ZZ Headcount',0.2,0.1),
('ZZR1','ZZIT',2,'ZZHR','ZZP2','ZZ Headcount',0.2,0.09),
('ZZR1','ZZHR',2,'ZZHR','ZZP1','ZZ Headcount',1,0.625),
('ZZR1','ZZHR',2,'ZZHR','ZZP2','ZZ Headcount',1,0.375000000001);
