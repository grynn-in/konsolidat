{# konsol#348 PR3 (BUD-10-1, no silent fallback): a budget line is stated against a declared Regular period.

   A budget belongs to a period the calendar declares (epm_staging.fiscal_periods, period_type 'Regular').
   A line in a Closing, Opening or Adjustment period, or in a period the calendar does not declare, has no
   window to be judged against: the hierarchy-node models inner-join the declared periods, so such a line
   would drop out of the node reports unnamed. This test names it. Checked on the raw lines
   (epm_raw.budget_entries) and on the fact (gold_spread_budget).

   One row per (source, scenario, entity, year, period). Error severity: the budget would be wrong.
   Fixtures: dbt_project/test_fixtures/assert_budget_period_declared*.sql. #}
{{ config(severity='error') }}

with regular as (
    select toUInt16(fiscal_year) as fiscal_year, toUInt16(fiscal_period) as fiscal_period
    from {{ source('epm_staging', 'fiscal_periods') }}
    where period_type = 'Regular'
    group by fiscal_year, fiscal_period
)

select
    'epm_raw.budget_entries' as source,
    scenario_id,
    data_area_id,
    toUInt16(fiscal_year) as fiscal_year,
    toUInt16(fiscal_period) as fiscal_period,
    count() as n_rows,
    'budget period is not a declared Regular period' as fault
from {{ source('budget_raw', 'budget_entries') }}
where (toUInt16(fiscal_year), toUInt16(fiscal_period)) not in (select fiscal_year, fiscal_period from regular)
group by scenario_id, data_area_id, fiscal_year, fiscal_period

union all

select
    'gold_spread_budget' as source,
    scenario_id,
    data_area_id,
    toUInt16(fiscal_year) as fiscal_year,
    toUInt16(fiscal_period) as fiscal_period,
    count() as n_rows,
    'budget period is not a declared Regular period' as fault
from {{ ref('gold_spread_budget') }}
where (toUInt16(fiscal_year), toUInt16(fiscal_period)) not in (select fiscal_year, fiscal_period from regular)
group by scenario_id, data_area_id, fiscal_year, fiscal_period
