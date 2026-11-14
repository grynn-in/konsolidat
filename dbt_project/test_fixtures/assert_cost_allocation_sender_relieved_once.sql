-- konsol#269 W4 (T4) clean fixture. Origin ZZIT in account ZZ6000 is relieved by run ZZR1
-- only. The same account and origin in period 2 is relieved by run ZZR2 (a different
-- period), and ZZR3 relieves it in another entity. ZZHR sending at step 2 for origin
-- ZZIT is a pass-through, not a relief of ZZHR's own pool.
-- tables epm_gold.gold_cost_allocation
INSERT INTO epm_gold.gold_cost_allocation (run, scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, line_type, origin_member, step, sender_member, receiver_member, member, origin_amount, amount) VALUES
('ZZR1','ZZSC','ZZE1',2026,1,'ZZ6000','sent','ZZIT',1,'ZZIT','ZZP1','ZZIT',1000,-1000),
('ZZR1','ZZSC','ZZE1',2026,1,'ZZ6000','received','ZZIT',1,'ZZIT','ZZP1','ZZP1',1000,1000),
('ZZR2','ZZSC','ZZE1',2026,2,'ZZ6000','sent','ZZIT',1,'ZZIT','ZZP1','ZZIT',500,-500),
('ZZR3','ZZSC','ZZE2',2026,1,'ZZ6000','sent','ZZIT',1,'ZZIT','ZZP1','ZZIT',700,-700),
('ZZR4','ZZSC','ZZE1',2026,1,'ZZ6000','sent','ZZIT',2,'ZZHR','ZZP1','ZZHR',200,-200);
