{# konsolidat#171 2d (#355 re-review F1-a): a budget fact in a fiscal year/period the declared calendar does
   not have is invisible in the hierarchy budget/variance views (gold_budget_at_hierarchy_node and the
   budget-only rows of gold_variance_at_hierarchy_node inner-join declared_periods()). Budget Cycle and
   Budget Annual Input carry fiscal_year as a plain Int, so nothing else forces the year to exist.

   It is named here as a WARN, not an ERROR, so a budget for a year not yet declared never blocks the
   consolidation chain (an ERROR test with gold_trial_balance as a second parent would skip every child of
   gold_trial_balance under `dbt build`). Chosen under the 5 Nov 2026 standing rule (refuse / report:
   report); see #171 2d and the PR #355 re-review.

   One row per (scenario, entity, period) of budget not declared in epm_staging.fiscal_periods.
   Fixture: dbt_project/test_fixtures/assert_budget_period_declared.undeclared_year.must_flag.sql. #}
{{ config(severity='warn') }}

select
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
