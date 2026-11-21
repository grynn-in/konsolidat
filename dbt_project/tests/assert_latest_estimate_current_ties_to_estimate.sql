-- konsol#348 S6 pair A review M2 (S6-Q1 b, decided by Deepak Pai, 17 Nov 2026; S6-Q2 a):
-- gold_latest_estimate_current is gold_latest_estimate narrowed to each forecast pair's DECLARED current
-- round, and nothing else. konsol's `latest_estimate` Dataset (the Excel K.EPM latest-estimate read)
-- reads it and binds scenario_id, never cycle, so a second round in the view would be added to the
-- first. A view cannot drift from its own filter, but it can match nothing (a type mismatch in the tuple
-- IN) or be re-widened by a later edit; this ties it per (scenario, fiscal year, cycle): the view's row
-- count and period_amount sum must equal the estimate's for the declared cycle, and the view must hold
-- no cycle the declaration does not name. One row per mismatched key. Error severity: every Excel
-- latest-estimate read would be doubled or empty.
-- The two sides are a UNION ALL summed by key (never EXCEPT, konsolidat#361; never a join, whose
-- unmatched side reads '' under join_use_nulls=0). Output aliases differ from every column read.
-- Fixtures: assert_latest_estimate_current_ties_to_estimate.sql (R1 and R2 in the estimate, R2
-- declared: pass), assert_latest_estimate_current_ties_to_estimate.must_flag.sql (both rounds in the
-- view: 1 result, the undeclared R1 key).
{{ config(severity='error') }}

with sides as (
    select
        e.scenario_id as k_scenario,
        toUInt16(e.fiscal_year) as k_year,
        e.cycle as k_cycle,
        count() as declared_rows,
        sum(toFloat64(e.period_amount)) as declared_amount,
        toUInt64(0) as view_rows,
        toFloat64(0) as view_amount
    from {{ ref('gold_latest_estimate') }} as e
    where (e.scenario_id, toUInt16(e.fiscal_year), e.cycle) in (
        select scenario_id, toUInt16(fiscal_year), cycle
        from {{ ref('gold_forecast_current_round') }}
    )
    group by e.scenario_id, e.fiscal_year, e.cycle

    union all

    select
        v.scenario_id as k_scenario,
        toUInt16(v.fiscal_year) as k_year,
        v.cycle as k_cycle,
        toUInt64(0) as declared_rows,
        toFloat64(0) as declared_amount,
        count() as view_rows,
        sum(toFloat64(v.period_amount)) as view_amount
    from {{ ref('gold_latest_estimate_current') }} as v
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
