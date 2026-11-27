-- konsol#269 phase 2b-1 W3 clean fixture: every Account Set weight still equals the
-- trial balance it was derived from.
-- ZZR1 (ZZE1, ZZSC, 2026 P3, dim_cost_center). ZZ Revenue reads ZZ4000 Reversed:
--   ZZP1 -100 -> 100, ZZP2 -300 -> 300. ZZ Units reads ZZ7000 + ZZ7100 As Booked:
--   ZZP1 10 + 5 = 15; ZZP2 has a 0 row, a real zero, and the weight says 0.
-- Rows on another account (ZZ4100), period (P2), entity (ZZE2) and scenario (ZZSD) are
--   not read for ZZR1. The P2 row IS read for ZZR2, period 2 of the same entity: -55 -> 55.
-- idx 5 (statistic) and idx 6 (fixed) carry values with no trial balance behind them
--   and are not derived rows, so they are not compared.
-- tables epm_gold.gold_scenario_trial_balance
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZR1','ZZRS1','Step-Down','dim_cost_center','Sender''s Own Accounts','','Follow Latest Data','ZZE1','ZZSC',2026,3),
('ZZR2','ZZRS1','Direct','dim_cost_center','Sender''s Own Accounts','','Follow Latest Data','ZZE1','ZZSC',2026,2);
INSERT INTO epm_staging.cost_allocation_run_driver_accounts (parent, idx, driver, main_account, value_sign) VALUES
('ZZR1',1,'ZZ Revenue','ZZ4000','Reversed'),
('ZZR1',2,'ZZ Units','ZZ7000','As Booked'),
('ZZR1',3,'ZZ Units','ZZ7100','As Booked'),
('ZZR2',1,'ZZ Revenue','ZZ4000','Reversed');
INSERT INTO epm_gold.gold_scenario_trial_balance (scenario_id, data_area_id, fiscal_year, fiscal_period, main_account, dim_cost_center, amount) VALUES
('ZZSC','ZZE1',2026,3,'ZZ4000','ZZP1',-100),
('ZZSC','ZZE1',2026,3,'ZZ4000','ZZP2',-300),
('ZZSC','ZZE1',2026,3,'ZZ4100','ZZP1',999),
('ZZSC','ZZE1',2026,2,'ZZ4000','ZZP1',-55),
('ZZSC','ZZE2',2026,3,'ZZ4000','ZZP1',-77),
('ZZSD','ZZE1',2026,3,'ZZ4000','ZZP1',-88),
('ZZSC','ZZE1',2026,3,'ZZ7000','ZZP1',10),
('ZZSC','ZZE1',2026,3,'ZZ7100','ZZP1',5),
('ZZSC','ZZE1',2026,3,'ZZ7000','ZZP2',0);
INSERT INTO epm_staging.cost_allocation_run_weights (parent, idx, step, sender_member, receiver_member, driver, statistic, value_period, carried_forward, driver_value, source, effective_from) VALUES
('ZZR1',1,1,'ZZIT','ZZP1','ZZ Revenue','',3,0,100,'Account Set','1970-01-01'),
('ZZR1',2,1,'ZZIT','ZZP2','ZZ Revenue','',3,0,300,'Account Set','1970-01-01'),
('ZZR1',3,2,'ZZHR','ZZP1','ZZ Units','',3,0,15,'Account Set','1970-01-01'),
('ZZR1',4,2,'ZZHR','ZZP2','ZZ Units','',3,0,0,'Account Set','1970-01-01'),
('ZZR1',5,3,'ZZFI','ZZP1','ZZ Headcount','ZZ Headcount',3,0,10,'Uploaded Statistic','1970-01-01'),
('ZZR1',6,3,'ZZFI','ZZP2','ZZ Floor Area','',3,0,7,'Fixed Weights','2026-01-01'),
('ZZR2',1,1,'ZZIT','ZZP1','ZZ Revenue','',2,0,55,'Account Set','1970-01-01');
