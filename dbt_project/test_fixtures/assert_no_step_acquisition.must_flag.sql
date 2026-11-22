-- gate: expect assert_no_step_acquisition flag 1
-- Must-flag fixture for assert_no_step_acquisition (konsolidat#348 stopgap): `dbt test --select
-- assert_no_step_acquisition` must FAIL with `Got 1 result`.
--
-- Group ZZG held 30% of ZZS under the equity method from 2025-01-01, then bought control on 2026-03-15
-- (Business Combination BC-ZZG-ZZS-2026-03-15, 80%, whose own Ownership Period starts that day). The deal is a
-- step acquisition: the earlier period is effective before the deal and does not carry the deal's date. The
-- test names the deal (BC-ZZG-ZZS-2026-03-15), the earlier holding's start (2025-01-01) and method (equity).
-- The earlier stake ends on 2026-03-14, the day before the deal: still held immediately before it, so it is a step.
-- Expected: one row.
--
-- The deal tables do not exist live yet: the gate creates, empty, the tables this fixture names, with their
-- DDL: epm_staging.business_combinations, epm_staging.ownership_periods.
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, acquisition_date)
VALUES
  ('ZZG', 'ZZS', '2025-01-01', '2026-03-14', 30, 'equity', '1900-01-01'),
  ('ZZG', 'ZZS', '2026-03-15', '9999-12-31', 80, 'full', '2026-03-15');
INSERT INTO epm_staging.business_combinations
  (name, consolidation_group, acquired_entity, acquisition_date, share_acquired_pct, consideration_currency, total_consideration, net_assets_acquired, fair_value_adjustments, goodwill, bargain_purchase_gain, nci_at_acquisition, ownership_period)
VALUES
  ('BC-ZZG-ZZS-2026-03-15', 'ZZG', 'ZZS', '2026-03-15', 80, 'USD', 2000, 1000, 0, 1200, 0, 200, 'OP-ZZG-ZZS-2026-03-15');
