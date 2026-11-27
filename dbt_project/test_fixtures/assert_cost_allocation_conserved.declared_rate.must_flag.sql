-- gate: expect assert_cost_allocation_conserved flag 2
-- konsol#269 2b-2 W4(a) must-flag fixture: two origins of the rate worked example (run ZZRT,
-- see assert_cost_allocation_conserved.declared_rate.sql) park money at a share sender.
-- Origin ZZIT (rate 50, own sent 950): ZZHR passes only 156.25 of the 250 it received on;
--   every hop still cancels (total 0) but the sinks ZZSA and ZZOP receive 856.25, not 950.
-- Origin ZZHR (pool 400): 50 of it is received at ZZHR itself, a share sender; the sinks get 350.
-- Run ZZRS is the clean Reciprocal shape of the pass fixture (a rate sender keeps what it
-- receives, its own returning units included) and is not flagged.
-- tables epm_gold.gold_cost_allocation
INSERT INTO epm_gold.gold_cost_allocation (run, main_account, pool_account, line_type, hop_kind, basis, origin_member, step, sender_member, receiver_member, member, origin_amount, amount) VALUES
('ZZRT','ZZ6999','ZZ6999','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZHR','ZZIT',50,-250),
('ZZRT','ZZ6999','ZZ6999','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZHR','ZZHR',50,250),
('ZZRT','ZZ6999','ZZ6999','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZSA','ZZIT',50,-400),
('ZZRT','ZZ6999','ZZ6999','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZSA','ZZSA',50,400),
('ZZRT','ZZ6999','ZZ6999','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZOP','ZZIT',50,-300),
('ZZRT','ZZ6999','ZZ6999','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZOP','ZZOP',50,300),
('ZZRT','ZZ6999','ZZ6999','sent','pass','Declared Rate','ZZIT',2,'ZZHR','ZZSA','ZZHR',50,-156.25),
('ZZRT','ZZ6999','ZZ6999','received','pass','Declared Rate','ZZIT',2,'ZZHR','ZZSA','ZZSA',50,156.25),
('ZZRT','ZZ6000','ZZ6000','sent','own','Share of Pool','ZZHR',2,'ZZHR','ZZSA','ZZHR',400,-250),
('ZZRT','ZZ6999','ZZ6000','received','own','Share of Pool','ZZHR',2,'ZZHR','ZZSA','ZZSA',400,250),
('ZZRT','ZZ6000','ZZ6000','sent','own','Share of Pool','ZZHR',2,'ZZHR','ZZOP','ZZHR',400,-150),
('ZZRT','ZZ6999','ZZ6000','received','own','Share of Pool','ZZHR',2,'ZZHR','ZZOP','ZZOP',400,100),
('ZZRT','ZZ6999','ZZ6000','received','own','Share of Pool','ZZHR',2,'ZZHR','ZZHR','ZZHR',400,50),
('ZZRS','ZZ6999','ZZ6999','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZHR','ZZIT',50,-250),
('ZZRS','ZZ6999','ZZ6999','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZHR','ZZHR',50,250),
('ZZRS','ZZ6999','ZZ6999','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZSA','ZZIT',50,-400),
('ZZRS','ZZ6999','ZZ6999','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZSA','ZZSA',50,400),
('ZZRS','ZZ6999','ZZ6999','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZOP','ZZIT',50,-300),
('ZZRS','ZZ6999','ZZ6999','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZOP','ZZOP',50,300),
('ZZRS','ZZ6999','ZZ6999','sent','pass','Declared Rate','ZZIT',2,'ZZHR','ZZIT','ZZHR',50,-50),
('ZZRS','ZZ6999','ZZ6999','received','pass','Declared Rate','ZZIT',2,'ZZHR','ZZIT','ZZIT',50,50),
('ZZRS','ZZ6999','ZZ6999','sent','pass','Declared Rate','ZZIT',2,'ZZHR','ZZSA','ZZHR',50,-200),
('ZZRS','ZZ6999','ZZ6999','received','pass','Declared Rate','ZZIT',2,'ZZHR','ZZSA','ZZSA',50,200),
('ZZRS','ZZ6000','ZZ6000','sent','own','Share of Pool','ZZHR',2,'ZZHR','ZZIT','ZZHR',400,-80),
('ZZRS','ZZ6999','ZZ6000','received','own','Share of Pool','ZZHR',2,'ZZHR','ZZIT','ZZIT',400,80),
('ZZRS','ZZ6000','ZZ6000','sent','own','Share of Pool','ZZHR',2,'ZZHR','ZZSA','ZZHR',400,-320),
('ZZRS','ZZ6999','ZZ6000','received','own','Share of Pool','ZZHR',2,'ZZHR','ZZSA','ZZSA',400,320);
