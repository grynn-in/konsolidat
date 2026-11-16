-- konsol#348 S4 (W4, S4-Q2 a): a budget fact row names a Budget Cycle that is not approved.
-- gold_consolidated_budget_tb consolidates the APPROVED Cycles only: it joins gold_spread_budget
-- to epm_staging.budget_cycles (konsol's write-through of submitted Cycles, which carries the
-- Cycle's Rate Set) on the Cycle's name, and a row whose Cycle has no row there is not translated.
-- That is correct (a Cycle still being entered has no declared rates to translate at), but it must
-- not be silent: this test names every (scenario, cycle) the fact holds and the consolidation does
-- not. Warn, not error: approved budget lines under a Cycle not yet approved are a normal state of
-- entry, and a draft budget must never stop the build.
-- NOT IN rather than a LEFT JOIN null test (join_use_nulls=0).
{{ config(severity='warn') }}

select
    scenario_id,
    cycle,
    count() as fact_rows,
    min(fiscal_year) as first_year,
    max(fiscal_year) as last_year
from {{ ref('gold_spread_budget') }}
where cycle not in (select name from {{ source('epm_staging', 'budget_cycles') }})
group by scenario_id, cycle
order by scenario_id, cycle
