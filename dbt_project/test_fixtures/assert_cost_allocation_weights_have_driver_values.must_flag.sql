-- gate: expect assert_cost_allocation_weights_have_driver_values flag 4
-- konsol#269 W4 (T2) must-flag fixture. Run ZZR1 is period 3; six weight rows, four wrong.
-- idx 1 ok. idx 2 ok (carried from period 2, value 28).
-- idx 3 flagged: the statistic has no value for member ZZP9.
-- idx 4 flagged: weight 31 differs from the submitted 30.
-- idx 5 flagged: carried row whose value_period equals the run period (3).
-- idx 6 flagged: not carried, but value_period 2 is not the run period.
-- tables epm_staging.cost_allocation_runs, epm_staging.cost_allocation_run_weights, epm_staging.cost_allocation_statistics, epm_staging.cost_allocation_statistic_values
CREATE TABLE IF NOT EXISTS epm_staging.cost_allocation_runs (name String, rule_set String, method String, allocation_dimension String, receiver_account_mode String, allocation_account String, amounts_after_approval String, data_area_id String, scenario_id String, fiscal_year UInt16, fiscal_period UInt8, computed_at DateTime) ENGINE = MergeTree ORDER BY name;
CREATE TABLE IF NOT EXISTS epm_staging.cost_allocation_run_weights (parent String, idx UInt32, step UInt16, sender_member String, receiver_member String, driver String, statistic String, value_period UInt8, carried_forward UInt8, driver_value Decimal(38,9)) ENGINE = MergeTree ORDER BY (parent, idx);
CREATE TABLE IF NOT EXISTS epm_staging.cost_allocation_statistics (name String, driver String, dimension String, data_area_id String, scenario_id String, fiscal_year UInt16) ENGINE = MergeTree ORDER BY name;
CREATE TABLE IF NOT EXISTS epm_staging.cost_allocation_statistic_values (parent String, idx UInt32, fiscal_period UInt8, member String, value Decimal(38,9)) ENGINE = MergeTree ORDER BY (parent, idx);
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZR1','ZZRS1','Direct','dim_cost_center','Same Account','','Follow Latest Data','ZZE1','ZZSC',2026,3);
INSERT INTO epm_staging.cost_allocation_statistics (name, driver, dimension, data_area_id, scenario_id, fiscal_year) VALUES
('ZZ Headcount','ZZ Headcount','dim_cost_center','ZZE1','ZZSC',2026);
INSERT INTO epm_staging.cost_allocation_statistic_values (parent, idx, fiscal_period, member, value) VALUES
('ZZ Headcount',1,3,'ZZP1',10),
('ZZ Headcount',2,3,'ZZP2',30),
('ZZ Headcount',3,2,'ZZP2',28);
INSERT INTO epm_staging.cost_allocation_run_weights (parent, idx, step, sender_member, receiver_member, driver, statistic, value_period, carried_forward, driver_value) VALUES
('ZZR1',1,1,'ZZIT','ZZP1','ZZ Headcount','ZZ Headcount',3,0,10),
('ZZR1',2,1,'ZZIT','ZZP2','ZZ Headcount','ZZ Headcount',2,1,28),
('ZZR1',3,1,'ZZIT','ZZP9','ZZ Headcount','ZZ Headcount',3,0,5),
('ZZR1',4,1,'ZZHR','ZZP2','ZZ Headcount','ZZ Headcount',3,0,31),
('ZZR1',5,1,'ZZHR','ZZP1','ZZ Headcount','ZZ Headcount',3,1,10),
('ZZR1',6,1,'ZZHR','ZZP2','ZZ Headcount','ZZ Headcount',2,0,28);
