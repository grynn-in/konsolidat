-- gate: expect assert_cost_allocation_balanced_per_account flag 8
-- konsol#269 WF1 must-flag fixture, seeded gold_cost_allocation read as it stands.
-- ZZRA (declared, allocation account ZZ6999; pool ZZIT 1000 on ZZ6000): ZZIT -> ZZHR .2,
--   ZZP1 .8; ZZHR passes its 200 on to ZZP1, but that sent line is on the pool account
--   ZZ6000 (the over-relief of review H2): ZZHR does not net to zero on ZZ6000 (1) nor on
--   ZZ6999 (2); the line is off the allocation account (3); ZZ6000 is relieved 1200 for
--   a pool of 1000 (4) and ZZ6999 carries 1200 for 1000 received (5).
-- ZZRB (own accounts; pool ZZIT 10,000,000.1234, coefficient 1): the hop amount overflowed
--   to 1,597,176.39 (review H1), so ZZIT is not relieved by its pool (6).
-- ZZRC (own accounts; pool ZZIT 100 on ZZ6000): ZZP1 receives on ZZ6100, so ZZ6000 (7)
--   and ZZ6100 (8) do not net to zero.
-- ZZRE (declared; ZZIT 500 on ZZ6000 to ZZP1 on ZZ6999) is correct and not flagged.
-- tables epm_gold.gold_cost_allocation, epm_staging.cost_allocation_runs
INSERT INTO epm_staging.cost_allocation_runs (name, receiver_account_mode, allocation_account, amounts_after_approval) VALUES
('ZZRA','Declared Allocation Account','ZZ6999','Follow Latest Data'),
('ZZRB','Sender''s Own Accounts','','Follow Latest Data'),
('ZZRC','Sender''s Own Accounts','','Follow Latest Data'),
('ZZRE','Declared Allocation Account','ZZ6999','Follow Latest Data');
INSERT INTO epm_gold.gold_cost_allocation (run, main_account, line_type, origin_member, step, sender_member, receiver_member, member, origin_amount, amount) VALUES
('ZZRA','ZZ6000','sent','ZZIT',1,'ZZIT','ZZHR','ZZIT',1000,-200),
('ZZRA','ZZ6999','received','ZZIT',1,'ZZIT','ZZHR','ZZHR',1000,200),
('ZZRA','ZZ6000','sent','ZZIT',1,'ZZIT','ZZP1','ZZIT',1000,-800),
('ZZRA','ZZ6999','received','ZZIT',1,'ZZIT','ZZP1','ZZP1',1000,800),
('ZZRA','ZZ6000','sent','ZZIT',2,'ZZHR','ZZP1','ZZHR',1000,-200),
('ZZRA','ZZ6999','received','ZZIT',2,'ZZHR','ZZP1','ZZP1',1000,200),
('ZZRB','ZZ6000','sent','ZZIT',1,'ZZIT','ZZP1','ZZIT',10000000.1234,-1597176.39),
('ZZRB','ZZ6000','received','ZZIT',1,'ZZIT','ZZP1','ZZP1',10000000.1234,1597176.39),
('ZZRC','ZZ6000','sent','ZZIT',1,'ZZIT','ZZP1','ZZIT',100,-100),
('ZZRC','ZZ6100','received','ZZIT',1,'ZZIT','ZZP1','ZZP1',100,100),
('ZZRE','ZZ6000','sent','ZZIT',1,'ZZIT','ZZP1','ZZIT',500,-500),
('ZZRE','ZZ6999','received','ZZIT',1,'ZZIT','ZZP1','ZZP1',500,500);
