{# konsolidat#171 / #252 (task 2a): every (fiscal_year, fiscal_period) that gold_trial_balance carries is
   declared in konsol's fiscal calendar (epm_staging.fiscal_periods), and declared with one span.

   The ownership window is judged on the declared period dates (macros/declared_periods.sql). A period the
   calendar does not declare has no dates, so there is nothing true to judge it on: it is refused here, at
   ERROR severity, and never judged at a date invented from the period number (the first of calendar month
   P, or the last day of that month). An undeclared period drops out of gold_entity_ownership, and so out of
   the consolidated trial balance; this test is what makes that drop a failed build instead of a silent one.

   A period declared on several rows with different start or end dates is refused for the same reason:
   the window would have to pick one span.

   The budget facts are judged the same way (#355 review F1). gold_budget_at_hierarchy_node and the
   budget-only rows of gold_variance_at_hierarchy_node inner-join the declared calendar, and Budget Cycle /
   Budget Annual Input carry fiscal_year as a plain Int, so nothing else forces the year to exist. A budget
   in an undeclared (fiscal_year, fiscal_period) would vanish from the hierarchy views without a word; here
   it is named, with its scenario and entity (source 'budget', read from gold_spread_budget).

   One row per (entity, period) not declared, per (scenario, entity, period) of budget not declared, and
   one row per period declared with conflicting spans. Column `source` says which: trial_balance, budget,
   calendar.
   Fixture: dbt_project/test_fixtures/assert_trial_balance_period_declared.must_flag.sql. #}
select
    'trial_balance' as source,
    '' as scenario_id,
    tb.data_area_id as data_area_id,
    toUInt16(tb.fiscal_year) as fiscal_year,
    toUInt16(tb.fiscal_period) as fiscal_period,
    count() as n_rows,
    'period not declared in epm_staging.fiscal_periods' as fault
from {{ ref('gold_trial_balance') }} as tb
where (toUInt16(tb.fiscal_year), toUInt16(tb.fiscal_period)) not in (
    select toUInt16(fiscal_year), toUInt16(fiscal_period)
    from {{ source('epm_staging', 'fiscal_periods') }}
)
group by tb.data_area_id, tb.fiscal_year, tb.fiscal_period

union all

select
    'budget' as source,
    b.scenario_id as scenario_id,
    b.data_area_id as data_area_id,
    toUInt16(b.fiscal_year) as fiscal_year,
    toUInt16(b.fiscal_period) as fiscal_period,
    count() as n_rows,
    'period not declared in epm_staging.fiscal_periods' as fault
from {{ ref('gold_spread_budget') }} as b
where (toUInt16(b.fiscal_year), toUInt16(b.fiscal_period)) not in (
    select toUInt16(fiscal_year), toUInt16(fiscal_period)
    from {{ source('epm_staging', 'fiscal_periods') }}
)
group by b.scenario_id, b.data_area_id, b.fiscal_year, b.fiscal_period

union all

select
    'calendar' as source,
    '' as scenario_id,
    '' as data_area_id,
    toUInt16(fiscal_year) as fiscal_year,
    toUInt16(fiscal_period) as fiscal_period,
    count() as n_rows,
    'period declared with more than one span' as fault
from {{ source('epm_staging', 'fiscal_periods') }}
group by fiscal_year, fiscal_period
having uniqExact(start_date, end_date) > 1
