{{ config(severity='warn') }}
{#
    konsolidat#93 / konsol#103: every currency the consolidated trial balance
    translates must have exactly one approved governed Closing and one Average
    rate for its period, into the group's reporting currency, each a positive
    finite number. This names each key that doesn't, and why, in the shape a
    person fixes it: pre-fill or enter the rate in konsol's Group Exchange Rate
    and approve it (or cancel the extra one).

    severity warn, on purpose: this test depends on the model's upstream, so
    at error severity a failure made `dbt build` SKIP the model and its
    downstream, leaving the old figures in place and the run half-green. The
    model decides: its first pre_hook (governed_rate_guard, the same query,
    scoped to the run) stops the build before anything is deleted.
#}
select
    from_currency,
    to_currency,
    fy as fiscal_year,
    fp as fiscal_period,
    problem,
    multiIf(
        problem = 'missing', 'no approved governed Closing and Average rate (konsol Group Exchange Rate)',
        problem = 'duplicate', 'more than one approved governed rate of one type',
        'a governed rate that is zero, negative or not a finite number'
    ) as detail
from ({{ governed_rate_gaps(scoped=false) }})
