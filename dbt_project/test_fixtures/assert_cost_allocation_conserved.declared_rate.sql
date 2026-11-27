-- konsol#269 2b-2 W4(a) clean fixture: conservation with a Declared Rate origin.
-- Run ZZRT, the plan's worked example (section 3), Step-Down, Declared Allocation Account
-- ZZ6999. ZZIT charges a rate of 50 per ticket (tickets ZZHR 5, ZZSA 8, ZZOP 6): its
-- origin_amount is the RATE and its own relief, 950, sits on ZZ6999; its pool of 1,000 on
-- ZZ6000 is untouched (the 50 difference is its absorption variance). ZZHR, a share sender,
-- passes the 250 it received on 5/8 : 3/8 and relieves its own pool of 400 on ZZ6000.
--   Origin ZZIT: own sent 950; received at the sinks ZZSA (400 + 156.25) and ZZOP
--   (300 + 93.75) = 950.   Origin ZZHR: own sent 400; ZZSA 250 + ZZOP 150 = 400.
-- Run ZZRS shows that a rate sender is a sink for EVERY origin, itself included
-- (Reciprocal shape): origin ZZIT's own units come back from ZZHR (1 ticket, 50) and stop
-- at ZZIT; sinks ZZSA 600 + ZZOP 300 + ZZIT 50 = 950. Share origin ZZHR (pool 400) sends
-- 80 to ZZIT, which keeps it: sinks ZZIT 80 + ZZSA 320 = 400.
-- tables epm_gold.gold_cost_allocation
INSERT INTO epm_gold.gold_cost_allocation (run, main_account, pool_account, line_type, hop_kind, basis, origin_member, step, sender_member, receiver_member, member, coefficient, origin_amount, amount) VALUES
('ZZRT','ZZ6999','ZZ6999','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZHR','ZZIT',5,50,-250),
('ZZRT','ZZ6999','ZZ6999','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZHR','ZZHR',5,50,250),
('ZZRT','ZZ6999','ZZ6999','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZSA','ZZIT',8,50,-400),
('ZZRT','ZZ6999','ZZ6999','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZSA','ZZSA',8,50,400),
('ZZRT','ZZ6999','ZZ6999','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZOP','ZZIT',6,50,-300),
('ZZRT','ZZ6999','ZZ6999','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZOP','ZZOP',6,50,300),
('ZZRT','ZZ6999','ZZ6999','sent','pass','Declared Rate','ZZIT',2,'ZZHR','ZZSA','ZZHR',3.125,50,-156.25),
('ZZRT','ZZ6999','ZZ6999','received','pass','Declared Rate','ZZIT',2,'ZZHR','ZZSA','ZZSA',3.125,50,156.25),
('ZZRT','ZZ6999','ZZ6999','sent','pass','Declared Rate','ZZIT',2,'ZZHR','ZZOP','ZZHR',1.875,50,-93.75),
('ZZRT','ZZ6999','ZZ6999','received','pass','Declared Rate','ZZIT',2,'ZZHR','ZZOP','ZZOP',1.875,50,93.75),
('ZZRT','ZZ6000','ZZ6000','sent','own','Share of Pool','ZZHR',2,'ZZHR','ZZSA','ZZHR',0.625,400,-250),
('ZZRT','ZZ6999','ZZ6000','received','own','Share of Pool','ZZHR',2,'ZZHR','ZZSA','ZZSA',0.625,400,250),
('ZZRT','ZZ6000','ZZ6000','sent','own','Share of Pool','ZZHR',2,'ZZHR','ZZOP','ZZHR',0.375,400,-150),
('ZZRT','ZZ6999','ZZ6000','received','own','Share of Pool','ZZHR',2,'ZZHR','ZZOP','ZZOP',0.375,400,150),
('ZZRS','ZZ6999','ZZ6999','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZHR','ZZIT',5,50,-250),
('ZZRS','ZZ6999','ZZ6999','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZHR','ZZHR',5,50,250),
('ZZRS','ZZ6999','ZZ6999','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZSA','ZZIT',8,50,-400),
('ZZRS','ZZ6999','ZZ6999','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZSA','ZZSA',8,50,400),
('ZZRS','ZZ6999','ZZ6999','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZOP','ZZIT',6,50,-300),
('ZZRS','ZZ6999','ZZ6999','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZOP','ZZOP',6,50,300),
('ZZRS','ZZ6999','ZZ6999','sent','pass','Declared Rate','ZZIT',2,'ZZHR','ZZIT','ZZHR',1,50,-50),
('ZZRS','ZZ6999','ZZ6999','received','pass','Declared Rate','ZZIT',2,'ZZHR','ZZIT','ZZIT',1,50,50),
('ZZRS','ZZ6999','ZZ6999','sent','pass','Declared Rate','ZZIT',2,'ZZHR','ZZSA','ZZHR',4,50,-200),
('ZZRS','ZZ6999','ZZ6999','received','pass','Declared Rate','ZZIT',2,'ZZHR','ZZSA','ZZSA',4,50,200),
('ZZRS','ZZ6000','ZZ6000','sent','own','Share of Pool','ZZHR',2,'ZZHR','ZZIT','ZZHR',0.2,400,-80),
('ZZRS','ZZ6999','ZZ6000','received','own','Share of Pool','ZZHR',2,'ZZHR','ZZIT','ZZIT',0.2,400,80),
('ZZRS','ZZ6000','ZZ6000','sent','own','Share of Pool','ZZHR',2,'ZZHR','ZZSA','ZZHR',0.8,400,-320),
('ZZRS','ZZ6999','ZZ6000','received','own','Share of Pool','ZZHR',2,'ZZHR','ZZSA','ZZSA',0.8,400,320);
