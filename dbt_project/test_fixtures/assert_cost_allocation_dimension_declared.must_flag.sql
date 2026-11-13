-- gate: expect assert_cost_allocation_dimension_declared flag 3
-- konsol#269 W4 (T3) must-flag fixture. Three runs flagged, one clean.
-- ZZR1 clean. ZZR2 names a dimension that does not exist. ZZR3 names a declared
-- dimension that is not In Budget (dim_business_unit). ZZR4 names none.
-- tables epm_staging.cost_allocation_runs
CREATE TABLE IF NOT EXISTS epm_staging.cost_allocation_runs (name String, rule_set String, method String, allocation_dimension String, receiver_account_mode String, allocation_account String, amounts_after_approval String, data_area_id String, scenario_id String, fiscal_year UInt16, fiscal_period UInt8, computed_at DateTime) ENGINE = MergeTree ORDER BY name;
INSERT INTO epm_staging.cost_allocation_runs (name, rule_set, method, allocation_dimension, receiver_account_mode, allocation_account, amounts_after_approval, data_area_id, scenario_id, fiscal_year, fiscal_period) VALUES
('ZZR1','ZZRS1','Direct','dim_cost_center','Same Account','','Follow Latest Data','ZZE1','ZZSC',2026,1),
('ZZR2','ZZRS1','Direct','dim_zz_nothing','Same Account','','Follow Latest Data','ZZE1','ZZSC',2026,1),
('ZZR3','ZZRS1','Direct','dim_business_unit','Same Account','','Follow Latest Data','ZZE1','ZZSC',2026,1),
('ZZR4','ZZRS1','Direct','','Same Account','','Follow Latest Data','ZZE1','ZZSC',2026,1);
