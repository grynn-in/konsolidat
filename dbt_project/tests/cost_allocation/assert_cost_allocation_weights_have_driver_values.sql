-- Statistic weights match submitted driver values (konsol#269, T2; phase 2b-1 W2a).
-- Every weight row whose value came from an Uploaded Statistic must equal a value
-- of the named statistic at value_period and receiver_member, and the statistic
-- must belong to the run: same scenario, entity and fiscal year as the run, and
-- the weight's own driver (decision Q3: a weight never borrows another
-- scenario's, entity's or year's statistic).
-- A carried row (carried_forward = 1) reads an earlier period than the run's;
-- a non-carried row reads the run's own period.
-- Phase 2b-1 (Deepak Pai, 27 Nov 2026): a driver's value also comes from Fixed
-- Weights or an Account Set, and those rows cite no statistic. Only rows with
-- source = 'Uploaded Statistic' are judged here; '' is read the same way, because a
-- run synced before phase 2b carries '' and every such row was a statistic row.
-- The shape of the other sources is assert_cost_allocation_weight_source_valid;
-- the drift of an Account Set value is assert_cost_allocation_derived_driver_drift.
select
    w.parent as run, w.idx, w.statistic, w.driver, w.value_period, w.receiver_member,
    w.carried_forward, w.driver_value, r.fiscal_period as run_period
from {{ source('epm_staging', 'cost_allocation_run_weights') }} as w
inner join {{ source('epm_staging', 'cost_allocation_runs') }} as r on r.name = w.parent
where w.source in ('Uploaded Statistic', '')
    and (
        (w.parent, w.statistic, w.driver, w.value_period, w.receiver_member, w.driver_value) not in (
            select r2.name, s.name, s.driver, v.fiscal_period, v.member, v.value
            from {{ source('epm_staging', 'cost_allocation_runs') }} as r2
            inner join {{ source('epm_staging', 'cost_allocation_statistics') }} as s
                on s.scenario_id = r2.scenario_id
                and s.data_area_id = r2.data_area_id
                and s.fiscal_year = r2.fiscal_year
            inner join {{ source('epm_staging', 'cost_allocation_statistic_values') }} as v
                on v.parent = s.name
        )
        or (w.carried_forward = 1 and w.value_period >= r.fiscal_period)
        or (w.carried_forward = 0 and w.value_period != r.fiscal_period)
    )
