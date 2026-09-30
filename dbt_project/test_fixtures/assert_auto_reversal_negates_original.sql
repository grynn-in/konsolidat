-- V04 fixture (konsol#305-D2-2/D2-11, batch review 27 Sep finding 1): copy of
-- the V01 fixture assert_auto_reversal_generated.sql — tables
-- epm_staging.consolidation_adjustments
ALTER TABLE epm_staging.consolidation_adjustments ADD COLUMN IF NOT EXISTS reverse_fiscal_year UInt16 DEFAULT 0;
ALTER TABLE epm_staging.consolidation_adjustments ADD COLUMN IF NOT EXISTS reverse_fiscal_period UInt8 DEFAULT 0;
INSERT INTO epm_staging.consolidation_adjustments (consolidation_group, adjustment_type, journal_id, data_area_id, fiscal_year, fiscal_period, main_account, debit_amount, credit_amount, description, posted_by, status, approved_by, reverse_fiscal_year, reverse_fiscal_period) VALUES ('ZZG','topside','ZZJ-00001','ZZE1',2025,6,'ZZ1100',100,0,'d','zz','Approved','zz',2025,9), ('ZZG','topside','ZZJ-00001','ZZE2',2025,6,'ZZ2100',0,100,'c','zz','Approved','zz',2025,9), ('ZZG','topside','ZZJ-00002','ZZE1',2025,6,'ZZ1100',50,0,'d','zz','Approved','zz',0,0), ('ZZG','topside','ZZJ-00002','ZZE1',2025,6,'ZZ2100',0,50,'c','zz','Approved','zz',0,0);
