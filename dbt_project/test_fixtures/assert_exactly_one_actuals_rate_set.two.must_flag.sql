-- gate: expect assert_exactly_one_actuals_rate_set flag 1
-- assert_exactly_one_actuals_rate_set (konsol#348 S4-Q7 a): must FLAG one row. Two Rate Sets are
-- flagged Is Actuals; the actuals predicate would read both sets' rates and every key they share
-- would be a duplicate. Refused by name ("2 Rate Set(s) flagged Is Actuals ... Unflag all but one
-- of ZZACT, ZZACT2").
INSERT INTO epm_staging.rate_sets
  (rate_set, label, is_actuals)
VALUES
  ('ZZACT', 'ZZ actuals', 1),
  ('ZZACT2', 'ZZ actuals, second', 1),
  ('ZZBUD', 'ZZ budget 2026', 0);
