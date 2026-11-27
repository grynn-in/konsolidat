-- Weight rows have the shape their source declares (konsol#269 phase 2b-1, W2b).
-- A driver's value comes from one of three sources (Deepak Pai, 27 Nov 2026):
--   'Uploaded Statistic': the row cites a statistic; its match is
--     assert_cost_allocation_weights_have_driver_values. '' is the same thing on a
--     run synced before phase 2b, so '' is read as 'Uploaded Statistic' throughout.
--   'Fixed Weights': blank statistic, not carried, value_period = the run's period,
--     effective_from = the start of the window the value was read from (set).
--   'Account Set': blank statistic, not carried, value_period = the run's period,
--     effective_from unset (this Date column holds unset as 1970-01-01), and the run
--     holds at least one cost_allocation_run_driver_accounts row for the driver, each
--     with value_sign 'As Booked' or 'Reversed' (the drift test negates on 'Reversed';
--     any other sign would be read as 'As Booked', which this row forbids instead).
-- Only Fixed Weights carries a window start: a statistic or Account Set row with one
-- set is flagged too. One driver has one source inside a run: two sources for the
-- same (run, driver) flag every row of that driver.
-- One row per offending weight, with every reason it offends in `problems`.
-- Membership is tested with IN/NOT IN subqueries, not LEFT JOINs: join_use_nulls=0
-- would fill a missing side with '' and 0.
with judged as (
    select
        w.parent as run,
        w.idx,
        w.step,
        w.driver,
        w.source,
        w.statistic,
        w.value_period,
        r.fiscal_period as run_period,
        w.carried_forward,
        w.effective_from,
        w.source not in ('Uploaded Statistic', 'Fixed Weights', 'Account Set', '') as unknown_source,
        w.source in ('Fixed Weights', 'Account Set') and w.statistic != '' as cites_statistic,
        w.source in ('Fixed Weights', 'Account Set') and w.carried_forward = 1 as carried,
        w.source in ('Fixed Weights', 'Account Set') and w.value_period != r.fiscal_period as not_run_period,
        w.source = 'Fixed Weights' and w.effective_from = toDate('1970-01-01') as window_unset,
        w.source != 'Fixed Weights' and w.effective_from != toDate('1970-01-01') as window_set,
        w.source = 'Account Set' and (w.parent, w.driver) not in (
            select parent, driver
            from {{ source('epm_staging', 'cost_allocation_run_driver_accounts') }}
        ) as no_accounts,
        w.source = 'Account Set' and (w.parent, w.driver) in (
            select parent, driver
            from {{ source('epm_staging', 'cost_allocation_run_driver_accounts') }}
            where value_sign not in ('As Booked', 'Reversed')
        ) as bad_sign,
        (w.parent, w.driver) in (
            select parent, driver
            from {{ source('epm_staging', 'cost_allocation_run_weights') }}
            group by parent, driver
            having uniqExact(if(source = '', 'Uploaded Statistic', source)) > 1
        ) as two_sources
    from {{ source('epm_staging', 'cost_allocation_run_weights') }} as w
    inner join {{ source('epm_staging', 'cost_allocation_runs') }} as r on r.name = w.parent
)

select
    run, idx, step, driver, source, statistic, value_period, run_period, carried_forward, effective_from,
    arrayStringConcat(arrayFilter(x -> x != '', [
        if(unknown_source, 'source is not Uploaded Statistic, Fixed Weights or Account Set', ''),
        if(cites_statistic, 'a non-statistic row cites a statistic', ''),
        if(carried, 'a non-statistic row is carried forward', ''),
        if(not_run_period, 'a non-statistic row is not read at the run period', ''),
        if(window_unset, 'a Fixed Weights row has no window start', ''),
        if(window_set, 'only a Fixed Weights row carries a window start', ''),
        if(no_accounts, 'an Account Set row with no driver_accounts row in the run', ''),
        if(bad_sign, 'a driver_accounts value_sign is not As Booked or Reversed', ''),
        if(two_sources, 'the driver has two sources in this run', '')
    ]), '; ') as problems
from judged
where unknown_source or cites_statistic or carried or not_run_period
    or window_unset or window_set or no_accounts or bad_sign or two_sources
