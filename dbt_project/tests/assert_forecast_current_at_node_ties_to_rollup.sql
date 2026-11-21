-- konsol#348 S6 pair A review M2 (S6-Q1 b, decided by Deepak Pai, 17 Nov 2026):
-- gold_forecast_current_at_hierarchy_node is gold_budget_at_hierarchy_node narrowed to each forecast
-- pair's DECLARED current round, and nothing else. konsol's hierarchy forecast read (the Excel K.EPM
-- read at a reporting-hierarchy node) reads it and binds scenario_id and layer, never cycle, so a
-- second round in the view would be added to the first. A view cannot drift from its own filter, but
-- it can match nothing (a type mismatch in the tuple IN) or be re-widened by a later edit; this ties it
-- per (scenario, fiscal year, cycle): the view's row count and period_amount sum must equal the
-- rollup's for the declared cycle, and the view must hold no cycle the declaration does not name. One
-- row per mismatched key. Error severity: every hierarchy forecast read would be doubled or empty.
-- The two sides are a UNION ALL summed by key (never EXCEPT, konsolidat#361; never a join, whose
-- unmatched side reads '' under join_use_nulls=0). Output aliases differ from every column read.
-- Fixtures: assert_forecast_current_at_node_ties_to_rollup.sql (R1 100 and R2 110 at two nodes, R2
-- declared: pass), assert_forecast_current_at_node_ties_to_rollup.must_flag.sql (both rounds in the
-- view: 1 result, the undeclared R1 key).
{{ config(severity='error') }}

with sides as (
    select
        n.scenario_id as k_scenario,
        toUInt16(n.fiscal_year) as k_year,
        n.cycle as k_cycle,
        count() as declared_rows,
        sum(toFloat64(n.period_amount)) as declared_amount,
        toUInt64(0) as view_rows,
        toFloat64(0) as view_amount
    from {{ ref('gold_budget_at_hierarchy_node') }} as n
    where (n.scenario_id, toUInt16(n.fiscal_year), n.cycle) in (
        select scenario_id, toUInt16(fiscal_year), cycle
        from {{ ref('gold_forecast_current_round') }}
    )
    group by n.scenario_id, n.fiscal_year, n.cycle

    union all

    select
        v.scenario_id as k_scenario,
        toUInt16(v.fiscal_year) as k_year,
        v.cycle as k_cycle,
        toUInt64(0) as declared_rows,
        toFloat64(0) as declared_amount,
        count() as view_rows,
        sum(toFloat64(v.period_amount)) as view_amount
    from {{ ref('gold_forecast_current_at_hierarchy_node') }} as v
    group by v.scenario_id, v.fiscal_year, v.cycle
)

select
    k_scenario as forecast_scenario,
    k_year as key_year,
    k_cycle as round_cycle,
    sum(declared_rows) as declared_round_rows,
    sum(view_rows) as current_view_rows,
    sum(declared_amount) as declared_round_amount,
    sum(view_amount) as current_view_amount
from sides
group by k_scenario, k_year, k_cycle
having declared_round_rows != current_view_rows
    or abs(declared_round_amount - current_view_amount) > {{ materiality_floor() }}
