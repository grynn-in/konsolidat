-- gate: expect assert_cost_allocation_sender_relieved_once flag 2
-- konsol#269 W4 (T4) must-flag fixture. Two keys relieved by two runs each.
-- ZZIT / ZZ6000 / ZZE1 / 2026 / P1: relieved by ZZR1 and ZZR2 -> flagged.
-- ZZHR / ZZ6000 / ZZE1 / 2026 / P1: relieved by ZZR1 and ZZR3 -> flagged.
-- ZZIT / ZZ6000 / ZZE1 / 2026 / P2: relieved by ZZR4 alone -> clean.
-- tables epm_gold.gold_cost_allocation
INSERT INTO epm_gold.gold_cost_allocation (run, scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, line_type, origin_member, step, sender_member, receiver_member, member, origin_amount, amount) VALUES
('ZZR1','ZZSC','ZZE1',2026,1,'ZZ6000','sent','ZZIT',1,'ZZIT','ZZP1','ZZIT',1000,-1000),
('ZZR2','ZZSC','ZZE1',2026,1,'ZZ6000','sent','ZZIT',1,'ZZIT','ZZP2','ZZIT',1000,-1000),
('ZZR1','ZZSC','ZZE1',2026,1,'ZZ6000','sent','ZZHR',1,'ZZHR','ZZP1','ZZHR',400,-400),
('ZZR3','ZZSC','ZZE1',2026,1,'ZZ6000','sent','ZZHR',1,'ZZHR','ZZP1','ZZHR',400,-400),
('ZZR4','ZZSC','ZZE1',2026,2,'ZZ6000','sent','ZZIT',1,'ZZIT','ZZP1','ZZIT',500,-500);
