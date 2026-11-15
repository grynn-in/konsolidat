{# konsol#348 S3 B4 (QB2 a, decided 14 Nov 2026 under Deepak Pai's standing rule): the budget fact keeps
   every Budget Cycle apart.

   A forecast scenario holds one approved Cycle per round, and several rounds share one (scenario, fiscal
   year) by design (Q23 a; assert_budget_one_cycle_per_scenario_year leaves forecasts out for that reason).
   gold_spread_budget therefore carries `cycle`, and its manual branch groups by it. Rounds must never sum:
   a model that grouped the lines of one grain without the cycle would add round 2 to round 1 and report a
   budget nobody entered.

   Checked line by line. For every (cycle, scenario, layer, entity, year) whose epm_raw.budget_entries lines
   are all 'Period movement', the fact's manual rows per (cycle, scenario, layer, entity, year, period,
   account, budget dims) must equal the lines' debit - credit on that grain. A year-to-date slice is
   converted before it reaches the fact and is reconciled by assert_budget_ytd_reconciles; a slice that
   mixes bases is named by assert_budget_basis_supported; neither is read here.

   UNION ALL + GROUP BY, not a join: join_use_nulls=0 would fill a missing fact row with 0 and hide it.
   Here a missing side reads 0 and the difference names it.

   One row per grain whose fact differs from its lines by more than 0.01. Error severity: the budget fact
   would be wrong. Fixtures: dbt_project/test_fixtures/budget_fact_two_rounds.sql. #}
{{ config(severity='error') }}

with movement_slices as (
    select
        cycle,
        scenario_id,
        layer,
        data_area_id,
        toUInt16(fiscal_year) as fiscal_year
    from {{ source('budget_raw', 'budget_entries') }}
    group by cycle, scenario_id, layer, data_area_id, fiscal_year
    having countIf(amount_basis != 'Period movement') = 0
),

combined as (
    select
        cycle,
        scenario_id,
        layer,
        data_area_id,
        toUInt16(fiscal_year) as fiscal_year,
        toUInt8(fiscal_period) as fiscal_period,
        toString(main_account) as main_account,
        {{ dim_select(dims=get_budget_dimensions(), trailing=true) }}
        toFloat64(debit - credit) as line_amount,
        toFloat64(0) as fact_amount
    from {{ source('budget_raw', 'budget_entries') }}
    where amount_basis = 'Period movement'
      and (cycle, scenario_id, layer, data_area_id, toUInt16(fiscal_year)) in (
          select cycle, scenario_id, layer, data_area_id, fiscal_year from movement_slices
      )

    union all

    select
        cycle,
        scenario_id,
        layer,
        data_area_id,
        toUInt16(fiscal_year) as fiscal_year,
        toUInt8(fiscal_period) as fiscal_period,
        toString(main_account) as main_account,
        {{ dim_select(dims=get_budget_dimensions(), trailing=true) }}
        toFloat64(0) as line_amount,
        toFloat64(period_amount) as fact_amount
    from {{ ref('gold_spread_budget') }}
    where spread_profile_id = 'manual'
      and (cycle, scenario_id, layer, data_area_id, toUInt16(fiscal_year)) in (
          select cycle, scenario_id, layer, data_area_id, fiscal_year from movement_slices
      )
)

select
    cycle,
    scenario_id,
    layer,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    {{ dim_select(dims=get_budget_dimensions(), trailing=true) }}
    sum(line_amount) as line_net,
    sum(fact_amount) as fact_net
from combined
group by
    cycle,
    scenario_id,
    layer,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account
    {{- dim_group_by(dims=get_budget_dimensions(), leading=true) }}
having abs(sum(line_amount) - sum(fact_amount)) > 0.01
