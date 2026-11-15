-- konsol#348 S4-Q7 (a), chosen under the standing rule (15 Nov 2026): exactly one Rate Set is
-- flagged Is Actuals in epm_staging.rate_sets, or nothing consolidates. The actuals consolidation
-- (gold_consolidated_trial_balance, the deal journals, the equity-method journal, and every test
-- that reads a governed or historical rate) translates at that set's rates only, through
-- actuals_rate_set_predicate() in macros/governed_rates.sql. With zero flagged sets the predicate
-- selects no rate at all; with two it selects both sets' rates and every key is a duplicate. Neither
-- is a number anyone should read, so this test refuses at ERROR severity: in `dbt build` a failure
-- here skips gold_consolidated_trial_balance and everything downstream, by design, and the model's
-- own pre_hook guard (governed_rate_guard) refuses a selective build with the same count in its
-- message, before the scope's DELETE.
--
-- An existing stack whose konsol has not yet synced the table (reconcile_all creates and fills it;
-- konsol's patch creates and flags ACTUAL) has zero rows here and is refused by name, never built
-- at "every set" as before the column existed: the guard reads the count, not the old `1 = 1`.
-- The fixture gate seeds one flagged set ('ZZACT') in every fixture that seeds a rate or builds the
-- consolidated trial balance; the TB-only first build seeds ACTUAL (tests/test_rate_sets_ddl.py).
--
-- Fails (returns one row) when countIf(is_actuals = 1) != 1, naming the count and the flagged sets.
select
    count() as rate_sets,
    countIf(is_actuals = 1) as actuals_sets,
    arraySort(groupArrayIf(rate_set, is_actuals = 1)) as flagged,
    concat(
        'konsol#348: ', toString(countIf(is_actuals = 1)),
        ' Rate Set(s) flagged Is Actuals; exactly one is required. ',
        if(countIf(is_actuals = 1) = 0,
           'Declare the actuals set in konsol (Rate Set, Is Actuals) and let reconcile_all sync it.',
           concat('Unflag all but one of ', arrayStringConcat(arraySort(groupArrayIf(rate_set, is_actuals = 1)), ', '), '.'))
    ) as problem
from {{ source('epm_staging', 'rate_sets') }}
having countIf(is_actuals = 1) != 1
