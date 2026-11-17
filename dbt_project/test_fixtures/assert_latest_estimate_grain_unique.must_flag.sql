-- gate: expect assert_latest_estimate_grain_unique flag 1
-- konsol#348 S6 WA7: one row per key. gold_latest_estimate seeded straight into its table (test mode)
-- with R2's P6 twice on one key: the actual -60 and the forecast -66 (the as-of period on both sides).
-- One key, two rows: 1 result. R2's P7 forecast is alone on its key: not named.
-- Budget dimensions at the fixture dims are dim_cost_center and dim_department; the live table may have
-- been built at other dims, so they are added by ALTER first.
ALTER TABLE epm_gold.gold_latest_estimate ADD COLUMN IF NOT EXISTS dim_cost_center String;
ALTER TABLE epm_gold.gold_latest_estimate ADD COLUMN IF NOT EXISTS dim_department String;
INSERT INTO epm_gold.gold_latest_estimate
  (scenario_id, cycle, as_of_date, data_area_id, fiscal_year, fiscal_period, main_account,
   dim_cost_center, dim_department, currency, period_amount, source)
VALUES
  ('ZZ_FC_LE', 'ZZ-LE-R2', '2026-06-30', 'ZZE1', 2026, 6, 'ZZ4000', '', '', 'USD', -60, 'actual'),
  ('ZZ_FC_LE', 'ZZ-LE-R2', '2026-06-30', 'ZZE1', 2026, 6, 'ZZ4000', '', '', 'USD', -66, 'forecast'),
  ('ZZ_FC_LE', 'ZZ-LE-R2', '2026-06-30', 'ZZE1', 2026, 7, 'ZZ4000', '', '', 'USD', -72, 'forecast');
