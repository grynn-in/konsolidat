-- konsol#348 S4 (W8): every row of gold_consolidated_budget_tb carries a resolved translation rate,
-- the budget twin of assert_translation_rate_resolved (konsolidat#109, #194) over
-- gold_consolidated_trial_balance. The same two failure modes, both of which silently misstate
-- a translated budget:
--   1. translation_rate = 0: a LEFT-join miss defaulted the rate column to 0 (join_use_nulls=0)
--      and the row's translated, group and NCI amounts collapse to 0;
--   2. translation_rate IS NULL: a Nullable rate that escaped every rate branch of the core; the
--      core's throwIf and the budget_rate_guard pre_hook should have stopped the build first.
-- A cross-currency row translating at exactly 1.0 is NOT a failure (konsolidat#194): near-parity
-- pairs are quoted to 3 decimals, and the budget has no parity fallback: a Cycle whose Rate Set has
-- no usable rate for a key is refused by name before the table is replaced (budget_rate_guard), so
-- 1.0 here can only be a real quote in that set. Reports the Cycle and its Rate Set with the key,
-- so the row can be traced to the set it should have been translated at.
-- Fixture: test_fixtures/assert_budget_translation_rate_resolved.must_flag.sql.
{{ config(severity='error') }}

select
    consolidation_group,
    data_area_id,
    scenario_id,
    cycle,
    layer,
    rate_set,
    accounting_currency,
    reporting_currency,
    fiscal_year,
    fiscal_period,
    translation_rate
from {{ ref('gold_consolidated_budget_tb') }}
where translation_rate = 0
    or translation_rate is null
