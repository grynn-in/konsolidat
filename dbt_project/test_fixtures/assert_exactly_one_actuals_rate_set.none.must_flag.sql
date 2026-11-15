-- gate: expect assert_exactly_one_actuals_rate_set flag 1
-- assert_exactly_one_actuals_rate_set (konsol#348 S4-Q7 a): must FLAG one row. Rate Sets exist but
-- none is flagged Is Actuals, so the actuals consolidation has no set to read: refused by name
-- ("0 Rate Set(s) flagged Is Actuals"), never built at every set or at none. The same count stops a
-- selective build in gold_consolidated_trial_balance's guard
-- (assert_exactly_one_actuals_rate_set.guard_refuses.must_flag.sql).
INSERT INTO epm_staging.rate_sets
  (rate_set, label, is_actuals)
VALUES
  ('ZZBUD', 'ZZ budget 2026', 0),
  ('ZZFC', 'ZZ forecast 2026', 0);
