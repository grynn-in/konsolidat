-- gate: expect assert_ownership_exit_events pass
-- konsolidat#335 (option A, Deepak Pai, 14 Nov 2026), task X1: the exit events macro ownership_exits().
-- April fiscal years FY2024-FY2025 with Opening P0, Closing P13 and Adjustment P14, as .disposal_last_day.
-- Group ZZXG holds, all direct links at 100% full unless stated:
--   ZZXB bare end:    ends 2024-08-15 (inside FY2024 P5), no deal, no successor.  EXPECT one exit in FY2024 P5, the
--                     Regular period holding the end (#358 review F1; was P6); first not live P6, prev P5.
--   ZZXS successor:   ends 2024-08-15, a second full period starts 2024-08-16.       EXPECT none.
--   ZZXT transfer:    ZZXH1 holds it to 2024-08-15, ZZXH2 from 2024-08-16 (both nodes held by ZZXG). EXPECT none.
--   ZZXD disposal:    ends 2024-08-15 by a full Business Disposal.                   EXPECT none (the disposal journal derecognises it).
--   ZZXE boundary:    ends 2025-03-31, the last day of FY2024 P12, before Closing P13, Adjustment P14 and Opening P0.
--                     EXPECT one exit in FY2024 P12, the Regular period holding the end (#358 review F1; was the
--                     next Regular period, FY2025 P1); first not live FY2025 P1, prev FY2025 P0.
--   ZZXL live:        never ends.                                                   EXPECT none.
-- The test also checks every direct-link entity against an oracle built from ownership_periods and the calendar.
ALTER TABLE epm_staging.consolidation_ancestry ADD COLUMN IF NOT EXISTS path_id String, ADD COLUMN IF NOT EXISTS link_owner_group String, ADD COLUMN IF NOT EXISTS link_owner_data_area_id String;
ALTER TABLE epm_staging.ownership_periods ADD COLUMN IF NOT EXISTS owner_group String, ADD COLUMN IF NOT EXISTS owner_data_area_id String, MODIFY ORDER BY (consolidation_group, data_area_id, effective_date, owner_group, owner_data_area_id);
CREATE TABLE IF NOT EXISTS epm_staging.consolidation_method_declarations (consolidation_group String, data_area_id String, consolidation_method String, effective_date Date, end_date Date DEFAULT '9999-12-31', reason String, updated_at DateTime DEFAULT now()) ENGINE = ReplacingMergeTree(updated_at) ORDER BY (consolidation_group, data_area_id, effective_date);
CREATE TABLE IF NOT EXISTS epm_staging.business_disposals (name String, consolidation_group String, disposed_entity String, disposal_date Date, share_disposed_pct Float64, retained_interest_pct Float64, proceeds_currency String, total_proceeds Float64, ownership_period String) ENGINE = MergeTree ORDER BY name;
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2024, 0, 'FY2024-P00', 'FY2024 opening', 'Opening', '2024-04-01', '2024-04-01', '', 'Open'),
  (2024, 1, 'FY2024-P01', 'Apr 2024', 'Regular', '2024-04-01', '2024-04-30', 'Q1', 'Open'),
  (2024, 2, 'FY2024-P02', 'May 2024', 'Regular', '2024-05-01', '2024-05-31', 'Q1', 'Open'),
  (2024, 3, 'FY2024-P03', 'Jun 2024', 'Regular', '2024-06-01', '2024-06-30', 'Q1', 'Open'),
  (2024, 4, 'FY2024-P04', 'Jul 2024', 'Regular', '2024-07-01', '2024-07-31', 'Q2', 'Open'),
  (2024, 5, 'FY2024-P05', 'Aug 2024', 'Regular', '2024-08-01', '2024-08-31', 'Q2', 'Open'),
  (2024, 6, 'FY2024-P06', 'Sep 2024', 'Regular', '2024-09-01', '2024-09-30', 'Q2', 'Open'),
  (2024, 7, 'FY2024-P07', 'Oct 2024', 'Regular', '2024-10-01', '2024-10-31', 'Q3', 'Open'),
  (2024, 8, 'FY2024-P08', 'Nov 2024', 'Regular', '2024-11-01', '2024-11-30', 'Q3', 'Open'),
  (2024, 9, 'FY2024-P09', 'Dec 2024', 'Regular', '2024-12-01', '2024-12-31', 'Q3', 'Open'),
  (2024, 10, 'FY2024-P10', 'Jan 2025', 'Regular', '2025-01-01', '2025-01-31', 'Q4', 'Open'),
  (2024, 11, 'FY2024-P11', 'Feb 2025', 'Regular', '2025-02-01', '2025-02-28', 'Q4', 'Open'),
  (2024, 12, 'FY2024-P12', 'Mar 2025', 'Regular', '2025-03-01', '2025-03-31', 'Q4', 'Open'),
  (2024, 13, 'FY2024-P13', 'FY2024 closing', 'Closing', '2025-03-31', '2025-03-31', '', 'Open'),
  (2024, 14, 'FY2024-P14', 'FY2024 adjustment', 'Adjustment', '2025-03-31', '2025-03-31', '', 'Open'),
  (2025, 0, 'FY2025-P00', 'FY2025 opening', 'Opening', '2025-04-01', '2025-04-01', '', 'Open'),
  (2025, 1, 'FY2025-P01', 'Apr 2025', 'Regular', '2025-04-01', '2025-04-30', 'Q1', 'Open'),
  (2025, 2, 'FY2025-P02', 'May 2025', 'Regular', '2025-05-01', '2025-05-31', 'Q1', 'Open'),
  (2025, 3, 'FY2025-P03', 'Jun 2025', 'Regular', '2025-06-01', '2025-06-30', 'Q1', 'Open'),
  (2025, 4, 'FY2025-P04', 'Jul 2025', 'Regular', '2025-07-01', '2025-07-31', 'Q2', 'Open'),
  (2025, 5, 'FY2025-P05', 'Aug 2025', 'Regular', '2025-08-01', '2025-08-31', 'Q2', 'Open'),
  (2025, 6, 'FY2025-P06', 'Sep 2025', 'Regular', '2025-09-01', '2025-09-30', 'Q2', 'Open'),
  (2025, 7, 'FY2025-P07', 'Oct 2025', 'Regular', '2025-10-01', '2025-10-31', 'Q3', 'Open'),
  (2025, 8, 'FY2025-P08', 'Nov 2025', 'Regular', '2025-11-01', '2025-11-30', 'Q3', 'Open'),
  (2025, 9, 'FY2025-P09', 'Dec 2025', 'Regular', '2025-12-01', '2025-12-31', 'Q3', 'Open'),
  (2025, 10, 'FY2025-P10', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q4', 'Open'),
  (2025, 11, 'FY2025-P11', 'Feb 2026', 'Regular', '2026-02-01', '2026-02-28', 'Q4', 'Open'),
  (2025, 12, 'FY2025-P12', 'Mar 2026', 'Regular', '2026-03-01', '2026-03-31', 'Q4', 'Open'),
  (2025, 13, 'FY2025-P13', 'FY2025 closing', 'Closing', '2026-03-31', '2026-03-31', '', 'Open'),
  (2025, 14, 'FY2025-P14', 'FY2025 adjustment', 'Adjustment', '2026-03-31', '2026-03-31', '', 'Open');
INSERT INTO epm_staging.consolidation_ancestry
  (consolidation_group, data_area_id, link_group, link_data_area_id, link_depth, depth, path, path_id, link_owner_group, link_owner_data_area_id)
VALUES
  ('ZZXG', 'ZZXB', 'ZZXG', 'ZZXB', 1, 1, 'ZZXG/ZZXB', 'ZZXG/ZZXB', 'ZZXG', ''),
  ('ZZXG', 'ZZXS', 'ZZXG', 'ZZXS', 1, 1, 'ZZXG/ZZXS', 'ZZXG/ZZXS', 'ZZXG', ''),
  ('ZZXG', 'ZZXD', 'ZZXG', 'ZZXD', 1, 1, 'ZZXG/ZZXD', 'ZZXG/ZZXD', 'ZZXG', ''),
  ('ZZXG', 'ZZXE', 'ZZXG', 'ZZXE', 1, 1, 'ZZXG/ZZXE', 'ZZXG/ZZXE', 'ZZXG', ''),
  ('ZZXG', 'ZZXL', 'ZZXG', 'ZZXL', 1, 1, 'ZZXG/ZZXL', 'ZZXG/ZZXL', 'ZZXG', ''),
  ('ZZXG', 'ZZXH1', 'ZZXH1', 'ZZXH1', 1, 1, 'ZZXG/ZZXH1', 'ZZXG/ZZXH1', 'ZZXG', ''),
  ('ZZXG', 'ZZXH2', 'ZZXH2', 'ZZXH2', 1, 1, 'ZZXG/ZZXH2', 'ZZXG/ZZXH2', 'ZZXG', ''),
  ('ZZXG', 'ZZXT', 'ZZXH1', 'ZZXH1', 1, 2, 'ZZXG/ZZXH1/ZZXT', 'ZZXG/ZZXH1/ZZXT', 'ZZXG', ''),
  ('ZZXG', 'ZZXT', 'ZZXG', 'ZZXT', 2, 2, 'ZZXG/ZZXH1/ZZXT', 'ZZXG/ZZXH1/ZZXT', 'ZZXH1', 'ZZXH1'),
  ('ZZXG', 'ZZXT', 'ZZXH2', 'ZZXH2', 1, 2, 'ZZXG/ZZXH2/ZZXT', 'ZZXG/ZZXH2/ZZXT', 'ZZXG', ''),
  ('ZZXG', 'ZZXT', 'ZZXG', 'ZZXT', 2, 2, 'ZZXG/ZZXH2/ZZXT', 'ZZXG/ZZXH2/ZZXT', 'ZZXH2', 'ZZXH2');
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, owner_group, owner_data_area_id, is_disposal, disposal_date)
VALUES
  ('ZZXH1', 'ZZXH1', '2020-01-01', '2149-06-06', 100, 'full', 'ZZXG', '', 0, '9999-12-31'),
  ('ZZXH2', 'ZZXH2', '2020-01-01', '2149-06-06', 100, 'full', 'ZZXG', '', 0, '9999-12-31'),
  ('ZZXG', 'ZZXB', '2020-01-01', '2024-08-15', 100, 'full', 'ZZXG', '', 0, '9999-12-31'),
  ('ZZXG', 'ZZXS', '2020-01-01', '2024-08-15', 100, 'full', 'ZZXG', '', 0, '9999-12-31'),
  ('ZZXG', 'ZZXS', '2024-08-16', '2149-06-06', 80, 'full', 'ZZXG', '', 0, '9999-12-31'),
  ('ZZXG', 'ZZXT', '2020-01-01', '2024-08-15', 100, 'full', 'ZZXH1', 'ZZXH1', 0, '9999-12-31'),
  ('ZZXG', 'ZZXT', '2024-08-16', '2149-06-06', 100, 'full', 'ZZXH2', 'ZZXH2', 0, '9999-12-31'),
  ('ZZXG', 'ZZXD', '2020-01-01', '2024-08-15', 100, 'full', 'ZZXG', '', 1, '2024-08-15'),
  ('ZZXG', 'ZZXE', '2020-01-01', '2025-03-31', 100, 'full', 'ZZXG', '', 0, '9999-12-31'),
  ('ZZXG', 'ZZXL', '2020-01-01', '2149-06-06', 100, 'full', 'ZZXG', '', 0, '9999-12-31');
INSERT INTO epm_staging.business_disposals
  (name, consolidation_group, disposed_entity, disposal_date, share_disposed_pct, retained_interest_pct, proceeds_currency, total_proceeds, ownership_period)
VALUES
  ('BD-ZZXG-ZZXD-2024-08-15', 'ZZXG', 'ZZXD', '2024-08-15', 100, 0, 'USD', 1000, 'ZZ-OP-ZZXD-1');
