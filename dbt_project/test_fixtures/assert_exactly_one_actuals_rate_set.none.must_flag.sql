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
-- A trial balance, so the count rule applies: without a TB row there is nothing to translate and the
-- test passes on purpose (assert_exactly_one_actuals_rate_set.empty_stack.sql).
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZE1', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 100, 0, 100, 1);
