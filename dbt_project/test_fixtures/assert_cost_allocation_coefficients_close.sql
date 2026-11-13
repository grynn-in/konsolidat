-- konsol#269 W2 (T5) clean fixture: coefficients that close at every hop.
-- Origin ZZIT: step 1 sender ZZIT (pool 1) -> ZZHR .2, ZZP1 .5, ZZP2 .3;
-- step 2 sender ZZHR (pool .2) -> ZZP1 .1, ZZP2 .1.
-- Origin ZZHR: step 2 sender ZZHR (pool 1) -> ZZP1 .625, ZZP2 .375.
-- tables epm_staging.cost_allocation_coefficients
CREATE TABLE IF NOT EXISTS epm_staging.cost_allocation_coefficients (run String, origin_member String, step UInt16, sender_member String, receiver_member String, driver String, pool_coefficient Decimal(38,12), coefficient Decimal(38,12)) ENGINE = MergeTree ORDER BY (run, origin_member, step, receiver_member);
INSERT INTO epm_staging.cost_allocation_coefficients (run, origin_member, step, sender_member, receiver_member, driver, pool_coefficient, coefficient) VALUES
('ZZR1','ZZIT',1,'ZZIT','ZZHR','ZZ Headcount',1,0.2),
('ZZR1','ZZIT',1,'ZZIT','ZZP1','ZZ Headcount',1,0.5),
('ZZR1','ZZIT',1,'ZZIT','ZZP2','ZZ Headcount',1,0.3),
('ZZR1','ZZIT',2,'ZZHR','ZZP1','ZZ Headcount',0.2,0.1),
('ZZR1','ZZIT',2,'ZZHR','ZZP2','ZZ Headcount',0.2,0.1),
('ZZR1','ZZHR',2,'ZZHR','ZZP1','ZZ Headcount',1,0.625),
('ZZR1','ZZHR',2,'ZZHR','ZZP2','ZZ Headcount',1,0.375);
