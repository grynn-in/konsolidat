-- Derived (Account Set) weights that no longer match the trial balance
-- (konsol#269 phase 2b-1, W3; decision Q3 A, 27 Nov 2026: snapshot at Compute,
-- re-check at approval in konsol, warn on later drift here).
-- An Account Set driver's value is the sum of the scenario trial balance over the
-- driver's accounts, per receiver member, for the run's entity, scenario, year and
-- period, negated when the driver's value_sign is 'Reversed'. konsol reads it at
-- Compute and snapshots it on the run (driver_value) with the accounts it read
-- (cost_allocation_run_driver_accounts: one row per EXPANDED account, main_account,
-- with the declared account it came from, declared_account; 2b-1 DA). konsol walks
-- the account tree at Compute, so a group account on the driver arrives here as its
-- leaves and this test sums by main_account as stored, with no tree of its own
-- (ClickHouse has no recursive hierarchy). This test recomputes that sum from
-- gold_scenario_trial_balance as it stands now and names every weight row that
-- differs by more than 0.0000001, or whose member has no trial balance row at all
-- (konsol calls that member missing and would refuse the run; a 0 over rows is a
-- real zero and only drifts if the weight is not 0).
-- Warn, not error: an approved run keeps its weights by design; this tells the
-- accountant that the data they were derived from has moved since.
-- Dimension: the receiver member is read from the run's allocation_dimension through
-- cost_allocation_member_expr (the pools macro does the same). No staging table
-- carries a driver's dimension, and none is needed: konsol refuses a rule set whose
-- driver is on another dimension than the rule set's (cost_allocation_model.py,
-- "Driver %s is on dimension %s, not %s."), so the run's dimension IS the driver's.
-- A site with no budget dimensions reads '' and every derived row warns; T3
-- (assert_cost_allocation_dimension_declared) names the run.
-- declared_account is not read: the sum is over the expanded rows, and the sibling
-- weight-source test keys its "no driver_accounts row" rule on (parent, driver) alone.
-- LEFT JOIN on purpose: a member with no current rows must be reported. Both sides are
-- coalesced so the verdict is the same under join_use_nulls 0 (defaults) and 1 (NULL).
{{ config(severity='warn') }}
with runs as (
    select *
    from {{ source('epm_staging', 'cost_allocation_runs') }}
    where name in (
        select parent
        from {{ source('epm_staging', 'cost_allocation_run_weights') }}
        where source = 'Account Set'
    )
),

derived as (
    select parent as run, idx, step, sender_member, receiver_member, driver, driver_value
    from {{ source('epm_staging', 'cost_allocation_run_weights') }}
    where source = 'Account Set'
),

current_sums as (
    select
        r.name as run,
        da.driver as driver,
        {{ cost_allocation_member_expr('tb') }} as member,
        {{ cast_to_decimal128("sum(tb.amount * if(da.value_sign = 'Reversed', -1, 1))", 9) }} as current_value,
        count() as tb_rows
    from runs as r
    inner join {{ source('epm_staging', 'cost_allocation_run_driver_accounts') }} as da
        on da.parent = r.name
    inner join {{ ref('gold_scenario_trial_balance') }} as tb
        on tb.scenario_id = r.scenario_id
        and tb.data_area_id = r.data_area_id
        and tb.fiscal_year = r.fiscal_year
        and tb.fiscal_period = r.fiscal_period
        and tb.main_account = da.main_account
    group by r.name, da.driver, member
)

select
    d.run,
    d.idx,
    d.step,
    d.sender_member,
    d.receiver_member,
    d.driver,
    d.driver_value as snapshot_value,
    coalesce(c.current_value, toDecimal128('0', 9)) as current_value,
    coalesce(c.tb_rows, 0) as tb_rows
from derived as d
left join current_sums as c
    on c.run = d.run
    and c.driver = d.driver
    and c.member = d.receiver_member
where coalesce(c.tb_rows, 0) = 0
    or abs(d.driver_value - coalesce(c.current_value, toDecimal128('0', 9))) > toDecimal128('0.0000001', 9)
