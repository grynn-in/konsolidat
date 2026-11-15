-- assert_exactly_one_actuals_rate_set (konsol#348 S4-Q7 a): must PASS. One Rate Set is flagged Is
-- Actuals and a budget's set is not; the actuals consolidation has exactly one set to read.
INSERT INTO epm_staging.rate_sets
  (rate_set, label, is_actuals)
VALUES
  ('ZZACT', 'ZZ actuals', 1),
  ('ZZBUD', 'ZZ budget 2026', 0);
-- A trial balance, so the count rule applies: without a TB row there is nothing to translate and the
-- test passes on purpose (assert_exactly_one_actuals_rate_set.empty_stack.sql).
INSERT INTO epm_gold.gold_trial_balance
  (data_area_id, fiscal_year, fiscal_period, main_account, account_name, account_type_name, is_balance_sheet, is_pnl, period_debit, period_credit, period_net_amount, transaction_count)
VALUES
  ('ZZE1', 2026, 1, 'ZZ1000', 'ZZ cash', 'Asset', 1, 0, 100, 0, 100, 1);
