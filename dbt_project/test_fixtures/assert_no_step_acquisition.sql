-- gate: expect assert_no_step_acquisition pass
-- Passing fixture for assert_no_step_acquisition (konsolidat#348 stopgap): `dbt test --select
-- assert_no_step_acquisition` must PASS on the two deals a first acquisition looks like:
--   BC-ZZG-ZZS-2026-03-15: ZZS, no holding before the deal; its own period starts that day.
--   BC-ZZG-ZZT-2026-03-15: a migrated deal whose own Ownership Period is dated 2026-03-01, before the deal,
--     and carries the deal's acquisition_date. It is the deal's own period, not an earlier holding.
--   BC-ZZG-ZZU-2026-03-15: ZZU was held 40% from 2024-01-01 to 2025-06-30, fully divested, and bought again.
--     No stake is held the day before the deal, so it is a fresh acquisition with no previously held interest.
-- Expected: no rows.
--
-- The deal tables do not exist live yet: the gate creates, empty, the tables this fixture names, with their
-- DDL: epm_staging.business_combinations, epm_staging.ownership_periods.
INSERT INTO epm_staging.ownership_periods
  (consolidation_group, data_area_id, effective_date, end_date, ownership_pct, consolidation_method, acquisition_date)
VALUES
  ('ZZG', 'ZZS', '2026-03-15', '9999-12-31', 100, 'full', '2026-03-15'),
  ('ZZG', 'ZZT', '2026-03-01', '9999-12-31', 80, 'full', '2026-03-15'),
  ('ZZG', 'ZZU', '2024-01-01', '2025-06-30', 40, 'equity', '1900-01-01'),
  ('ZZG', 'ZZU', '2026-03-15', '9999-12-31', 80, 'full', '2026-03-15');
INSERT INTO epm_staging.business_combinations
  (name, consolidation_group, acquired_entity, acquisition_date, share_acquired_pct, consideration_currency, total_consideration, net_assets_acquired, fair_value_adjustments, goodwill, bargain_purchase_gain, nci_at_acquisition, ownership_period)
VALUES
  ('BC-ZZG-ZZS-2026-03-15', 'ZZG', 'ZZS', '2026-03-15', 100, 'USD', 1200, 1000, 0, 200, 0, 0, 'OP-ZZG-ZZS-2026-03-15'),
  ('BC-ZZG-ZZT-2026-03-15', 'ZZG', 'ZZT', '2026-03-15', 80, 'USD', 1200, 1000, 0, 400, 0, 200, 'OP-ZZG-ZZT-2026-03-01'),
  ('BC-ZZG-ZZU-2026-03-15', 'ZZG', 'ZZU', '2026-03-15', 80, 'USD', 1200, 1000, 0, 400, 0, 200, 'OP-ZZG-ZZU-2026-03-15');
