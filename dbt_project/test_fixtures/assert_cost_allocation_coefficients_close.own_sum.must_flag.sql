-- gate: expect assert_cost_allocation_coefficients_close flag 1
-- konsol#269 RC5 must-flag fixture: the origin's own hops sum to more than 1.
-- Origin ZZIT has two `own` hops, each closing against its own pool_coefficient
-- (.6 and .6), so no hop is flagged; the origin sends 1.2 of its pool. One row.
-- Origin ZZHR is clean: one own hop of 1.
-- tables epm_staging.cost_allocation_coefficients
CREATE TABLE IF NOT EXISTS epm_staging.cost_allocation_coefficients (run String, origin_member String, step UInt16, sender_member String, receiver_member String, driver String, hop_kind String, pool_coefficient Decimal(38,12), coefficient Decimal(38,12)) ENGINE = MergeTree ORDER BY (run, origin_member, step, receiver_member);
INSERT INTO epm_staging.cost_allocation_coefficients (run, origin_member, step, sender_member, receiver_member, driver, hop_kind, pool_coefficient, coefficient) VALUES
('ZZR1','ZZIT',1,'ZZIT','ZZP1','ZZ Headcount','own',0.6,0.6),
('ZZR1','ZZIT',2,'ZZIT','ZZP2','ZZ Headcount','own',0.6,0.6),
('ZZR1','ZZHR',2,'ZZHR','ZZP1','ZZ Headcount','own',1,1);
