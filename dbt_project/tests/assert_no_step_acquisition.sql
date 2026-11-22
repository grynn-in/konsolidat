{{ config(severity='error') }}
{#
    konsolidat#348, STOPGAP (decided 22 Nov 2026, Deepak Pai, "ship the refusal as a stopgap until Q1 C
    lands"). TEMPORARY: delete this test and its fixtures when Q1 C (full step acquisition,
    IFRS 3.41-3.42) is built; the refusal is lifted then, not kept.

    A Business Combination for an entity the group already held, under the equity method or in any
    earlier holding, is a step acquisition. Nothing in the warehouse handles one:
      - the days before the deal get no equity-method share (the method is read at the period end, so
        the whole deal period is controlled and pro-rating only removes the pre-deal days);
      - the old stake stays on the equity-method investment account (EQ_INVEST) and is never
        derecognised; and
      - it is never remeasured to fair value, so no gain or loss is booked (IFRS 3.42).
    No other test fails on it. konsol refuses the deal on submit (Business Combination,
    "step acquisitions are not supported yet"); this test is the backstop for a deal already in the
    warehouse, loaded before that refusal or from outside konsol, so the build fails by name.

    One row per deal. The earlier holding is an Ownership Period of the same group and entity that is
    effective before the deal date and still held the day before it (end_date on or after that day; an
    open period carries 9999-12-31). An entity fully divested earlier and bought again is a fresh
    acquisition with no previously held interest, so it is not named. The deal's own period is not earlier, whatever its effective date
    (a migrated deal's period may be dated before the deal): konsol stamps the period it creates or
    links with the deal's acquisition_date, so a period carrying THIS deal's date is its own. Only
    submitted rows reach the warehouse, so drafts and cancelled periods do not count.

    Fixtures: test_fixtures/assert_no_step_acquisition.must_flag.sql (30% equity, then a deal for
    the rest), assert_no_step_acquisition.sql (a first acquisition, and a deal whose own period is
    dated before it).
#}
select
    bc.name as business_combination,
    bc.consolidation_group,
    bc.acquired_entity,
    bc.acquisition_date,
    min(op.effective_date) as earlier_holding_from,
    argMin(op.consolidation_method, op.effective_date) as earlier_method,
    argMin(toFloat64(op.ownership_pct), op.effective_date) as earlier_ownership_pct,
    'step acquisitions are not supported yet (konsolidat#348): '
        || bc.acquired_entity || ' was already held by ' || bc.consolidation_group
        || ' before ' || toString(bc.acquisition_date) as reason
from {{ source('epm_staging', 'business_combinations') }} as bc
inner join {{ source('epm_staging', 'ownership_periods') }} as op
    on op.consolidation_group = bc.consolidation_group
    and op.data_area_id = bc.acquired_entity
where op.effective_date < bc.acquisition_date
  and op.acquisition_date != bc.acquisition_date
  and op.end_date >= subtractDays(bc.acquisition_date, 1)
group by bc.name, bc.consolidation_group, bc.acquired_entity, bc.acquisition_date
