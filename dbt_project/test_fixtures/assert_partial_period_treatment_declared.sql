-- gate: expect assert_partial_period_treatment_declared pass
-- konsolidat#171 step 2c (decisions: Deepak Pai, 18 Sep 2026; 10 Nov 2026 Q1 A). Companion: all three roots declare one of the three exact values, so mid-period deals are not flagged.
-- Calendar: calendar-month FY2026, P0 Opening and P13 Closing and P14 Adjustment on 2026-12-31 (never hold a deal).
-- Source rows are submitted deals only (the tables hold nothing else).
ALTER TABLE epm_gold.consolidation_groups ADD COLUMN IF NOT EXISTS partial_period_treatment String DEFAULT '';
CREATE TABLE IF NOT EXISTS epm_staging.business_combinations (name String, consolidation_group String, acquired_entity String, acquisition_date Date, share_acquired_pct Float64, consideration_currency String, total_consideration Float64, net_assets_acquired Float64, fair_value_adjustments Float64, goodwill Float64, bargain_purchase_gain Float64, nci_at_acquisition Float64, ownership_period String) ENGINE = MergeTree ORDER BY name;
CREATE TABLE IF NOT EXISTS epm_staging.business_disposals (name String, consolidation_group String, disposed_entity String, disposal_date Date, share_disposed_pct Float64, retained_interest_pct Float64, proceeds_currency String, total_proceeds Float64, ownership_period String) ENGINE = MergeTree ORDER BY name;
INSERT INTO epm_staging.fiscal_periods
  (fiscal_year, fiscal_period, period_code, period_label, period_type, start_date, end_date, quarter, status)
VALUES
  (2026, 0, 'FY2026-P00', 'Opening 2026', 'Opening', '2026-01-01', '2026-01-01', 'Q1', 'Open'),
  (2026, 1, 'FY2026-P01', 'Jan 2026', 'Regular', '2026-01-01', '2026-01-31', 'Q1', 'Open'),
  (2026, 2, 'FY2026-P02', 'Feb 2026', 'Regular', '2026-02-01', '2026-02-28', 'Q1', 'Open'),
  (2026, 3, 'FY2026-P03', 'Mar 2026', 'Regular', '2026-03-01', '2026-03-31', 'Q1', 'Open'),
  (2026, 4, 'FY2026-P04', 'Apr 2026', 'Regular', '2026-04-01', '2026-04-30', 'Q2', 'Open'),
  (2026, 5, 'FY2026-P05', 'May 2026', 'Regular', '2026-05-01', '2026-05-31', 'Q2', 'Open'),
  (2026, 6, 'FY2026-P06', 'Jun 2026', 'Regular', '2026-06-01', '2026-06-30', 'Q2', 'Open'),
  (2026, 7, 'FY2026-P07', 'Jul 2026', 'Regular', '2026-07-01', '2026-07-31', 'Q3', 'Open'),
  (2026, 8, 'FY2026-P08', 'Aug 2026', 'Regular', '2026-08-01', '2026-08-31', 'Q3', 'Open'),
  (2026, 9, 'FY2026-P09', 'Sep 2026', 'Regular', '2026-09-01', '2026-09-30', 'Q3', 'Open'),
  (2026, 10, 'FY2026-P10', 'Oct 2026', 'Regular', '2026-10-01', '2026-10-31', 'Q4', 'Open'),
  (2026, 11, 'FY2026-P11', 'Nov 2026', 'Regular', '2026-11-01', '2026-11-30', 'Q4', 'Open'),
  (2026, 12, 'FY2026-P12', 'Dec 2026', 'Regular', '2026-12-01', '2026-12-31', 'Q4', 'Open'),
  (2026, 13, 'FY2026-P13', 'Closing 2026', 'Closing', '2026-12-31', '2026-12-31', 'Q4', 'Open'),
  (2026, 14, 'FY2026-P14', 'Adjustment 2026', 'Adjustment', '2026-12-31', '2026-12-31', 'Q4', 'Open');
INSERT INTO epm_gold.consolidation_groups
  (consolidation_group, data_area_id, entity_name, reporting_currency, partial_period_treatment)
VALUES
  ('ZZG', '', 'ZZ ZZG', 'USD', 'Whole period'),
  ('ZZH', '', 'ZZ ZZH', 'USD', 'Pro-rate by days'),
  ('ZZK', '', 'ZZ ZZK', 'USD', 'Stub trial balance');
INSERT INTO epm_staging.business_combinations
  (name, consolidation_group, acquired_entity, acquisition_date, share_acquired_pct, consideration_currency, total_consideration, net_assets_acquired, fair_value_adjustments, goodwill, bargain_purchase_gain, nci_at_acquisition, ownership_period)
VALUES
  ('BC-ZZG-ZZS-2026-03-11', 'ZZG', 'ZZS', '2026-03-11', 100, 'USD', 1000, 800, 0, 200, 0, 0, ''),
  ('BC-ZZH-ZZW-2026-02-14', 'ZZH', 'ZZW', '2026-02-14', 100, 'USD', 1000, 800, 0, 200, 0, 0, ''),
  ('BC-ZZK-ZZX-2026-02-14', 'ZZK', 'ZZX', '2026-02-14', 100, 'USD', 1000, 800, 0, 200, 0, 0, '');
INSERT INTO epm_staging.business_disposals
  (name, consolidation_group, disposed_entity, disposal_date, share_disposed_pct, retained_interest_pct, proceeds_currency, total_proceeds, ownership_period)
VALUES
  ('BD-ZZG-ZZD-2026-09-20', 'ZZG', 'ZZD', '2026-09-20', 100, 0, 'USD', 1000, ''),
  ('BD-ZZH-ZZU-2026-06-15', 'ZZH', 'ZZU', '2026-06-15', 100, 0, 'USD', 1000, ''),
  ('BD-ZZK-ZZV-2026-05-10', 'ZZK', 'ZZV', '2026-05-10', 100, 0, 'USD', 1000, '');
