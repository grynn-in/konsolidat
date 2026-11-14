-- konsol#269 W4 (T3) clean fixture: both runs name an In Budget dimension of this project.
-- tables epm_staging.cost_allocation_runs
CREATE TABLE IF NOT EXISTS epm_staging.cost_allocation_runs (name String, rule_set String, method String, allocation_dimension String, receiver_account_mode String, allocation_account String, amounts_after_approval String, data_area_id String, scenario_id String, fiscal_year UInt16, fiscal_period UInt8, computed_at DateTime) ENGINE = MergeTree ORDER BY name;
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZR1','ZZRS1','Direct','dim_cost_center','Sender''s Own Accounts','','Follow Latest Data','ZZE1','ZZSC',2026,1),
('ZZR2','ZZRS1','Direct','dim_department','Sender''s Own Accounts','','Follow Latest Data','ZZE1','ZZSC',2026,2);
