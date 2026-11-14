-- konsol#269 W2 (T1) clean fixture: a step-down allocation that conserves.
-- Run ZZR1 on ZZ6000. Origin ZZIT pool 1000: ZZIT -> ZZHR 200, ZZP1 500, ZZP2 300
-- (step 1); ZZHR passes its 200 on, ZZP1 100 and ZZP2 100 (step 2). Origin ZZHR
-- pool 400: ZZP1 250, ZZP2 150. Every origin sums to 0 and lands its pool at
-- ZZP1/ZZP2, the members that never send.
-- tables epm_gold.gold_cost_allocation
INSERT INTO epm_gold.gold_cost_allocation (run, main_account, line_type, origin_member, step, sender_member, receiver_member, member, origin_amount, amount) VALUES
('ZZR1','ZZ6000','sent','ZZIT',1,'ZZIT','ZZHR','ZZIT',1000,-200),
('ZZR1','ZZ6000','received','ZZIT',1,'ZZIT','ZZHR','ZZHR',1000,200),
('ZZR1','ZZ6000','sent','ZZIT',1,'ZZIT','ZZP1','ZZIT',1000,-500),
('ZZR1','ZZ6000','received','ZZIT',1,'ZZIT','ZZP1','ZZP1',1000,500),
('ZZR1','ZZ6000','sent','ZZIT',1,'ZZIT','ZZP2','ZZIT',1000,-300),
('ZZR1','ZZ6000','received','ZZIT',1,'ZZIT','ZZP2','ZZP2',1000,300),
('ZZR1','ZZ6000','sent','ZZIT',2,'ZZHR','ZZP1','ZZHR',1000,-100),
('ZZR1','ZZ6000','received','ZZIT',2,'ZZHR','ZZP1','ZZP1',1000,100),
('ZZR1','ZZ6000','sent','ZZIT',2,'ZZHR','ZZP2','ZZHR',1000,-100),
('ZZR1','ZZ6000','received','ZZIT',2,'ZZHR','ZZP2','ZZP2',1000,100),
('ZZR1','ZZ6000','sent','ZZHR',2,'ZZHR','ZZP1','ZZHR',400,-250),
('ZZR1','ZZ6000','received','ZZHR',2,'ZZHR','ZZP1','ZZP1',400,250),
('ZZR1','ZZ6000','sent','ZZHR',2,'ZZHR','ZZP2','ZZHR',400,-150),
('ZZR1','ZZ6000','received','ZZHR',2,'ZZHR','ZZP2','ZZP2',400,150);
