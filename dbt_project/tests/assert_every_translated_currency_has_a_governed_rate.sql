{{ config(severity='warn') }}
{#
    konsolidat#93 / konsol#103: every currency the consolidated trial balance
    translates must have an APPROVED governed Closing and Average rate for its
    period, into the group's reporting currency. This names each gap, in the
    shape a person fixes it: pre-fill or enter the rate in konsol's Group
    Exchange Rate and approve it.

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
    'no approved governed Closing and Average rate (konsol Group Exchange Rate)' as problem
from ({{ governed_rate_gaps(scoped=false) }})
