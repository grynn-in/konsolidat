-- konsol#348 S4 (W5): every currency the consolidated budget translates has a usable governed rate
-- IN ITS CYCLE'S Rate Set, for its rate period. A budget translates at the set its Budget Cycle
-- declares (BUD-3; epm_staging.budget_cycles.rate_set), never at the actuals set and never at 1.0,
-- so a rate approved only in the actuals set leaves the budget key missing here. One row per
-- (scenario, cycle, rate set, from-currency, group reporting currency, rate year, rate period) with
-- the reason: missing (no approved Closing and Average rate in that set), duplicate (more than one
-- of a type in that set), invalid (zero, negative or not finite), implausible (more than 10x from
-- the two currencies' reference magnitudes, when both are known).
-- Built from the same macro as the model's pre_hook guard (budget_rate_gaps(), macros/
-- budget_rates.sql): the guard stops the budget build on the first 50 keys, this test lists all.
-- The keys are the model's own: the approved Cycles' fact rows, the entity's currency, the groups
-- the entity line-consolidates into at that period (ownership resolved on the budget's spine), the
-- group's reporting currency, same-currency rows excluded, the period mapped through
-- rate_period_map(). The actuals' twin is assert_every_translated_currency_has_a_governed_rate;
-- neither reads the other's keys, so a missing budget rate never stops the actuals build, and a
-- missing actuals rate never stops the budget. The rate rows are read through
-- budget_rate_set_predicate, the budget's rate_set_predicate: the Cycles' sets, counted per set.
{{ config(severity='error') }}

select *
from ({{ budget_rate_gaps() }})
order by scenario_id, cycle, rate_set, from_currency, to_currency, fy, fp
