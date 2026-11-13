-- gate: expect assert_cost_allocation_conserved flag 2
-- konsol#269 W2 (T1) must-flag fixture, two broken origins in run ZZR1.
-- Origin ZZIT: ZZP2 receives 299 for the 300 sent, so the lines sum to -1 and
-- the receivers' total (999) is not the pool (1000).
-- Origin ZZHR (pool 400): the lines sum to 0 but 50 is received at ZZHR itself,
-- a sender, so only 350 reaches the members that never send.
-- tables epm_gold.gold_cost_allocation
INSERT INTO epm_gold.gold_cost_allocation (run, main_account, line_type, origin_member, step, sender_member, receiver_member, member, origin_amount, amount) VALUES
('ZZR1','ZZ6000','sent','ZZIT',1,'ZZIT','ZZHR','ZZIT',1000,-200),
('ZZR1','ZZ6000','received','ZZIT',1,'ZZIT','ZZHR','ZZHR',1000,200),
('ZZR1','ZZ6000','sent','ZZIT',1,'ZZIT','ZZP1','ZZIT',1000,-500),
('ZZR1','ZZ6000','received','ZZIT',1,'ZZIT','ZZP1','ZZP1',1000,500),
('ZZR1','ZZ6000','sent','ZZIT',1,'ZZIT','ZZP2','ZZIT',1000,-300),
('ZZR1','ZZ6000','received','ZZIT',1,'ZZIT','ZZP2','ZZP2',1000,299),
('ZZR1','ZZ6000','sent','ZZIT',2,'ZZHR','ZZP1','ZZHR',1000,-100),
('ZZR1','ZZ6000','received','ZZIT',2,'ZZHR','ZZP1','ZZP1',1000,100),
('ZZR1','ZZ6000','sent','ZZIT',2,'ZZHR','ZZP2','ZZHR',1000,-100),
('ZZR1','ZZ6000','received','ZZIT',2,'ZZHR','ZZP2','ZZP2',1000,100),
('ZZR1','ZZ6000','sent','ZZHR',2,'ZZHR','ZZP1','ZZHR',400,-250),
('ZZR1','ZZ6000','received','ZZHR',2,'ZZHR','ZZP1','ZZP1',400,250),
('ZZR1','ZZ6000','sent','ZZHR',2,'ZZHR','ZZP2','ZZHR',400,-150),
('ZZR1','ZZ6000','received','ZZHR',2,'ZZHR','ZZP2','ZZP2',400,100),
('ZZR1','ZZ6000','received','ZZHR',2,'ZZHR','ZZHR','ZZHR',400,50);
