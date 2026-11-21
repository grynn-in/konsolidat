-- konsol#348 S6-Q1 (b), decided by Deepak Pai, 17 Nov 2026 (#348 comment 6953756459): gold_forecast_current
-- is gold_spread_budget narrowed to each forecast pair's DECLARED current round, and nothing else. It is
-- what konsol's `forecast_input` Dataset (the Excel K.EPM forecast read) reads instead of the fact, so a
-- read of a forecast scenario sums one round, never two. A view cannot drift from its own filter, but it
-- can match nothing (a type mismatch in the tuple IN would leave it empty while the fact holds the round)
-- or be re-widened by a later edit (the "plain copy" that summed rounds); this ties it per (scenario,
-- fiscal year, cycle): the view's row count and period_amount sum must equal the fact's for the declared
-- cycle, and the view must hold no cycle the declaration does not name. One row per mismatched key.
-- Error severity: every Excel forecast read would be doubled or empty.
-- join_use_nulls=0: the missing side reads '' (coalesce(..., '') = '' covers both settings); output
-- aliases differ from the joined columns' names.
-- Fixtures: assert_forecast_current_ties_to_fact.sql (R1 100, R2 110, R2 declared: the view holds R2's
-- row alone, pass), assert_forecast_current_ties_to_fact.must_flag.sql (the view seeded with both rounds,
-- the pre-S6 shape: 1 result, the undeclared R1 key).
{{ config(severity='error') }}

with expected as (
    select
        f.scenario_id as scenario_id,
        toUInt16(f.fiscal_year) as fiscal_year,
        f.cycle as cycle,
        count() as fact_rows,
        sum(toFloat64(f.period_amount)) as fact_amount
    from {{ ref('gold_spread_budget') }} as f
    where (f.scenario_id, toUInt16(f.fiscal_year), f.cycle) in (
        select scenario_id, toUInt16(fiscal_year), cycle
        from {{ ref('gold_forecast_current_round') }}
    )
    group by f.scenario_id, f.fiscal_year, f.cycle
),

current_view as (
    select
        v.scenario_id as view_scenario,
        toUInt16(v.fiscal_year) as view_year,
        v.cycle as view_cycle,
        count() as view_rows,
        sum(toFloat64(v.period_amount)) as view_amount
    from {{ ref('gold_forecast_current') }} as v
    group by v.scenario_id, v.fiscal_year, v.cycle
)

select
    if(coalesce(e.scenario_id, '') != '', e.scenario_id, c.view_scenario) as forecast_scenario,
    if(coalesce(e.scenario_id, '') != '', e.fiscal_year, c.view_year) as key_year,
    if(coalesce(e.scenario_id, '') != '', e.cycle, c.view_cycle) as round_cycle,
    e.fact_rows as declared_round_rows,
    c.view_rows as current_view_rows,
    e.fact_amount as declared_round_amount,
    c.view_amount as current_view_amount
from expected as e
full outer join current_view as c
    on c.view_scenario = e.scenario_id
    and c.view_year = e.fiscal_year
    and c.view_cycle = e.cycle
where coalesce(e.scenario_id, '') = ''
   or coalesce(c.view_scenario, '') = ''
   or e.fact_rows != c.view_rows
   or abs(e.fact_amount - c.view_amount) > {{ materiality_floor() }}
