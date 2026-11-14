-- gate: expect assert_cost_allocation_frozen_consistent flag 3
-- konsol#269 W5 must-flag fixture: three runs, one problem each.
-- ZZRD (Freeze at Approval): the hop is in the table twice.
-- ZZRG: lines for a run that is not in staging (a cancelled run left behind).
-- ZZRS (Follow Latest Data): a live run carrying a frozen_at.
-- tables epm_gold.gold_cost_allocation, epm_staging.cost_allocation_runs
INSERT INTO epm_staging.cost_allocation_runs (name, amounts_after_approval) VALUES
('ZZRD','Freeze at Approval'),
('ZZRS','Follow Latest Data');
INSERT INTO epm_gold.gold_cost_allocation (run, main_account, line_type, origin_member, step, sender_member, receiver_member, member, origin_amount, amount, frozen_at) VALUES
('ZZRD','ZZ6000','sent','ZZIT',1,'ZZIT','ZZP1','ZZIT',100,-100,'2026-11-01 10:00:00'),
('ZZRD','ZZ6000','sent','ZZIT',1,'ZZIT','ZZP1','ZZIT',100,-100,'2026-11-01 10:00:00'),
('ZZRD','ZZ6000','received','ZZIT',1,'ZZIT','ZZP1','ZZP1',100,100,'2026-11-01 10:00:00'),
('ZZRG','ZZ6000','sent','ZZIT',1,'ZZIT','ZZP1','ZZIT',100,-100,'2026-11-01 10:00:00'),
('ZZRG','ZZ6000','received','ZZIT',1,'ZZIT','ZZP1','ZZP1',100,100,'2026-11-01 10:00:00'),
('ZZRS','ZZ6000','sent','ZZIT',1,'ZZIT','ZZP1','ZZIT',100,-100,'2026-11-01 10:00:00'),
('ZZRS','ZZ6000','received','ZZIT',1,'ZZIT','ZZP1','ZZP1',100,100,'2026-11-01 10:00:00');
