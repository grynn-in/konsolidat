-- konsol#348 S2 (Q16-c, one writer per grain; decided 13 Nov 2026 under Deepak Pai's standing rule).
-- gold_spread_budget sums manual lines without the cycle, so two Cycles with lines on one
-- (scenario, fiscal year) would be added together: a doubled budget. konsol's intake keeps one Cycle
-- per (scenario, year); this is the warehouse backstop, one row per (scenario, fiscal year) that
-- epm_raw.budget_entries holds under more than one cycle. epm_gold.budget_annual_input carries no
-- cycle column, so the annual side has nothing to check here (n/a).
-- Error severity: the budget fact would be wrong.
{{ config(severity='error') }}

select
    scenario_id,
    fiscal_year,
    groupUniqArray(cycle) as cycles
from {{ source('budget_raw', 'budget_entries') }}
group by scenario_id, fiscal_year
having uniqExact(cycle) > 1
