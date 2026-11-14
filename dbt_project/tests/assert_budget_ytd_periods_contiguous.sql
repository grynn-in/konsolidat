-- konsol#348 S2 (Q15-c, Q21-a): a Year-to-date slice states every period from 1 to its last.
-- Q21-a was chosen under the standing rule (#348 comment 6875869375). konsol refuses the same
-- slices at intake; this is the build-time backstop.
-- gold_spread_budget differences a 'Year-to-date movement' series across the periods it states.
-- With P6 missing, P7 would be YTD7 - YTD5 (two months merged into one); with a first stated period
-- above 1, P1..Pn would merge into it. So every YTD (cycle, scenario, layer, entity, year) must state
-- exactly periods 1..max(stated period). One row per scope that does not. (The model reads no
-- declared-period calendar for budget lines, so the check is on the stated periods themselves.)
-- Error severity: the budget fact would be wrong.
{{ config(severity='error') }}

select
    cycle,
    scenario_id,
    layer,
    data_area_id,
    fiscal_year,
    min(fiscal_period) as first_period,
    max(fiscal_period) as last_period,
    uniqExact(fiscal_period) as periods_stated
from {{ source('budget_raw', 'budget_entries') }}
where amount_basis = 'Year-to-date movement'
group by cycle, scenario_id, layer, data_area_id, fiscal_year
having min(fiscal_period) != 1
    or uniqExact(fiscal_period) != max(fiscal_period)
