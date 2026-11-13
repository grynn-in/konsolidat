-- Weights match submitted driver values (konsol#269, T2). Every weight row of a
-- run must equal a value of the named statistic at value_period and
-- receiver_member. A carried row (carried_forward = 1) reads an earlier period
-- than the run's; a non-carried row reads the run's own period.
select
    w.parent as run, w.idx, w.statistic, w.value_period, w.receiver_member,
    w.carried_forward, w.driver_value, r.fiscal_period as run_period
from {{ source('epm_staging', 'cost_allocation_run_weights') }} as w
inner join {{ source('epm_staging', 'cost_allocation_runs') }} as r on r.name = w.parent
where (w.statistic, w.value_period, w.receiver_member, w.driver_value) not in (
        select s.name, v.fiscal_period, v.member, v.value
        from {{ source('epm_staging', 'cost_allocation_statistics') }} as s
        inner join {{ source('epm_staging', 'cost_allocation_statistic_values') }} as v
            on v.parent = s.name
    )
    or (w.carried_forward = 1 and w.value_period >= r.fiscal_period)
    or (w.carried_forward = 0 and w.value_period != r.fiscal_period)
