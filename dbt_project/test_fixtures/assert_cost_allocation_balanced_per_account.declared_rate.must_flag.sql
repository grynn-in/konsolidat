-- gate: expect assert_cost_allocation_balanced_per_account flag 3
-- konsol#269 2b-2 W4(c) must-flag fixture, seeded gold_cost_allocation read as it stands. Three
-- runs of the rate worked example (ZZIT charges 50 per ticket; ZZHR a share sender), one fault each.
-- ZZRA (declared, ZZ6999): ZZIT's own relief is booked on its pool account ZZ6000, not on the
--   allocation account (1: 'line not on the declared allocation account'). The accounts still
--   balance, because the relief is read from where it sits.
-- ZZRB (declared): the lines charge 950 (19 tickets) but the run's weights hold 20 tickets (ZZHR 6),
--   so the relief must be -1,000 (1: 'origin not relieved by exactly its pool').
-- ZZRC (Sender's Own Accounts): a Declared Rate origin in a run with no allocation account; its
--   charge has nowhere to go but the pool account (1: 'declared rate in Sender''s Own Accounts mode').
-- tables epm_gold.gold_cost_allocation, epm_staging.cost_allocation_runs, epm_staging.cost_allocation_run_weights
INSERT INTO epm_staging.cost_allocation_runs (name, receiver_account_mode, allocation_account, amounts_after_approval) VALUES
('ZZRA','Declared Allocation Account','ZZ6999','Follow Latest Data'),
('ZZRB','Declared Allocation Account','ZZ6999','Follow Latest Data'),
('ZZRC','Sender''s Own Accounts','','Follow Latest Data');
INSERT INTO epm_staging.cost_allocation_run_weights (parent, idx, step, sender_member, receiver_member, driver, statistic, value_period, carried_forward, driver_value, source, effective_from, basis, rate, rate_from) VALUES
('ZZRA',1,1,'ZZIT','ZZHR','ZZ Tickets','ZZ Tickets',1,0,5,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRA',2,1,'ZZIT','ZZSA','ZZ Tickets','ZZ Tickets',1,0,8,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRA',3,1,'ZZIT','ZZOP','ZZ Tickets','ZZ Tickets',1,0,6,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRB',1,1,'ZZIT','ZZHR','ZZ Tickets','ZZ Tickets',1,0,6,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRB',2,1,'ZZIT','ZZSA','ZZ Tickets','ZZ Tickets',1,0,8,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRB',3,1,'ZZIT','ZZOP','ZZ Tickets','ZZ Tickets',1,0,6,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRC',1,1,'ZZIT','ZZHR','ZZ Tickets','ZZ Tickets',1,0,5,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRC',2,1,'ZZIT','ZZSA','ZZ Tickets','ZZ Tickets',1,0,8,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01'),
('ZZRC',3,1,'ZZIT','ZZOP','ZZ Tickets','ZZ Tickets',1,0,6,'Uploaded Statistic','1970-01-01','Declared Rate',50,'2026-01-01');
INSERT INTO epm_gold.gold_cost_allocation (run, main_account, pool_account, line_type, hop_kind, basis, origin_member, step, sender_member, receiver_member, member, origin_amount, amount) VALUES
('ZZRA','ZZ6000','ZZ6000','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZHR','ZZIT',50,-250),
('ZZRA','ZZ6999','ZZ6000','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZHR','ZZHR',50,250),
('ZZRA','ZZ6000','ZZ6000','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZSA','ZZIT',50,-400),
('ZZRA','ZZ6999','ZZ6000','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZSA','ZZSA',50,400),
('ZZRA','ZZ6000','ZZ6000','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZOP','ZZIT',50,-300),
('ZZRA','ZZ6999','ZZ6000','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZOP','ZZOP',50,300),
('ZZRA','ZZ6999','ZZ6000','sent','pass','Declared Rate','ZZIT',2,'ZZHR','ZZSA','ZZHR',50,-156.25),
('ZZRA','ZZ6999','ZZ6000','received','pass','Declared Rate','ZZIT',2,'ZZHR','ZZSA','ZZSA',50,156.25),
('ZZRA','ZZ6999','ZZ6000','sent','pass','Declared Rate','ZZIT',2,'ZZHR','ZZOP','ZZHR',50,-93.75),
('ZZRA','ZZ6999','ZZ6000','received','pass','Declared Rate','ZZIT',2,'ZZHR','ZZOP','ZZOP',50,93.75),
('ZZRA','ZZ6000','ZZ6000','sent','own','Share of Pool','ZZHR',2,'ZZHR','ZZSA','ZZHR',400,-250),
('ZZRA','ZZ6999','ZZ6000','received','own','Share of Pool','ZZHR',2,'ZZHR','ZZSA','ZZSA',400,250),
('ZZRA','ZZ6000','ZZ6000','sent','own','Share of Pool','ZZHR',2,'ZZHR','ZZOP','ZZHR',400,-150),
('ZZRA','ZZ6999','ZZ6000','received','own','Share of Pool','ZZHR',2,'ZZHR','ZZOP','ZZOP',400,150),
('ZZRB','ZZ6999','ZZ6999','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZHR','ZZIT',50,-250),
('ZZRB','ZZ6999','ZZ6999','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZHR','ZZHR',50,250),
('ZZRB','ZZ6999','ZZ6999','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZSA','ZZIT',50,-400),
('ZZRB','ZZ6999','ZZ6999','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZSA','ZZSA',50,400),
('ZZRB','ZZ6999','ZZ6999','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZOP','ZZIT',50,-300),
('ZZRB','ZZ6999','ZZ6999','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZOP','ZZOP',50,300),
('ZZRB','ZZ6999','ZZ6999','sent','pass','Declared Rate','ZZIT',2,'ZZHR','ZZSA','ZZHR',50,-156.25),
('ZZRB','ZZ6999','ZZ6999','received','pass','Declared Rate','ZZIT',2,'ZZHR','ZZSA','ZZSA',50,156.25),
('ZZRB','ZZ6999','ZZ6999','sent','pass','Declared Rate','ZZIT',2,'ZZHR','ZZOP','ZZHR',50,-93.75),
('ZZRB','ZZ6999','ZZ6999','received','pass','Declared Rate','ZZIT',2,'ZZHR','ZZOP','ZZOP',50,93.75),
('ZZRB','ZZ6000','ZZ6000','sent','own','Share of Pool','ZZHR',2,'ZZHR','ZZSA','ZZHR',400,-250),
('ZZRB','ZZ6999','ZZ6000','received','own','Share of Pool','ZZHR',2,'ZZHR','ZZSA','ZZSA',400,250),
('ZZRB','ZZ6000','ZZ6000','sent','own','Share of Pool','ZZHR',2,'ZZHR','ZZOP','ZZHR',400,-150),
('ZZRB','ZZ6999','ZZ6000','received','own','Share of Pool','ZZHR',2,'ZZHR','ZZOP','ZZOP',400,150),
('ZZRC','ZZ6000','ZZ6000','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZHR','ZZIT',50,-250),
('ZZRC','ZZ6000','ZZ6000','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZHR','ZZHR',50,250),
('ZZRC','ZZ6000','ZZ6000','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZSA','ZZIT',50,-400),
('ZZRC','ZZ6000','ZZ6000','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZSA','ZZSA',50,400),
('ZZRC','ZZ6000','ZZ6000','sent','own','Declared Rate','ZZIT',1,'ZZIT','ZZOP','ZZIT',50,-300),
('ZZRC','ZZ6000','ZZ6000','received','own','Declared Rate','ZZIT',1,'ZZIT','ZZOP','ZZOP',50,300),
('ZZRC','ZZ6000','ZZ6000','sent','pass','Declared Rate','ZZIT',2,'ZZHR','ZZSA','ZZHR',50,-156.25),
('ZZRC','ZZ6000','ZZ6000','received','pass','Declared Rate','ZZIT',2,'ZZHR','ZZSA','ZZSA',50,156.25),
('ZZRC','ZZ6000','ZZ6000','sent','pass','Declared Rate','ZZIT',2,'ZZHR','ZZOP','ZZHR',50,-93.75),
('ZZRC','ZZ6000','ZZ6000','received','pass','Declared Rate','ZZIT',2,'ZZHR','ZZOP','ZZOP',50,93.75),
('ZZRC','ZZ6000','ZZ6000','sent','own','Share of Pool','ZZHR',2,'ZZHR','ZZSA','ZZHR',400,-250),
('ZZRC','ZZ6000','ZZ6000','received','own','Share of Pool','ZZHR',2,'ZZHR','ZZSA','ZZSA',400,250),
('ZZRC','ZZ6000','ZZ6000','sent','own','Share of Pool','ZZHR',2,'ZZHR','ZZOP','ZZHR',400,-150),
('ZZRC','ZZ6000','ZZ6000','received','own','Share of Pool','ZZHR',2,'ZZHR','ZZOP','ZZOP',400,150);
