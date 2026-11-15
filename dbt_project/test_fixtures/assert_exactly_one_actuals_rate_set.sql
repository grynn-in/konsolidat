-- assert_exactly_one_actuals_rate_set (konsol#348 S4-Q7 a): must PASS. One Rate Set is flagged Is
-- Actuals and a budget's set is not; the actuals consolidation has exactly one set to read.
INSERT INTO epm_staging.rate_sets
  (rate_set, label, is_actuals)
VALUES
  ('ZZACT', 'ZZ actuals', 1),
  ('ZZBUD', 'ZZ budget 2026', 0);
