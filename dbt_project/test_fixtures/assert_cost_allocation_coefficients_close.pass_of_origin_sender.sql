-- gate: expect assert_cost_allocation_coefficients_close pass
-- konsol#269 RC5 clean fixture: a `pass` hop whose sender is the origin itself (the
-- Reciprocal shape: the origin receives from HR and passes the amount on). It is not
-- the origin's own relief, so its pool_coefficient need not be 1; only the `own`
-- hops of an origin must sum to 1. A test that reads sender = origin as own relief
-- flags it wrongly.
-- Origin ZZIT: own step 1 (sender ZZIT, pool 1) -> ZZHR .4, ZZP1 .6;
-- pass step 2 (sender ZZIT, pool .4) -> ZZP1 .4.
-- tables epm_staging.cost_allocation_coefficients
CREATE TABLE IF NOT EXISTS epm_staging.cost_allocation_coefficients (run String, origin_member String, step UInt16, sender_member String, receiver_member String, driver String, hop_kind String, pool_coefficient Decimal(38,12), coefficient Decimal(38,12)) ENGINE = MergeTree ORDER BY (run, origin_member, step, receiver_member);
INSERT INTO epm_staging.cost_allocation_coefficients (run, origin_member, step, sender_member, receiver_member, driver, hop_kind, pool_coefficient, coefficient) VALUES
('ZZR1','ZZIT',1,'ZZIT','ZZHR','ZZ Headcount','own',1,0.4),
('ZZR1','ZZIT',1,'ZZIT','ZZP1','ZZ Headcount','own',1,0.6),
('ZZR1','ZZIT',2,'ZZIT','ZZP1','ZZ Headcount','pass',0.4,0.4);
