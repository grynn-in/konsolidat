{{
    config(
        materialized='view',
        schema='gold'
    )
}}

{# konsol#348 S6 WC1 (S6-Q7 a, under the standing rule): the K.EPM-queryable shape of the GROUP-level
   consolidated budget, as gold_consolidated_fact is for the actuals.

   gold_fully_consolidated_budget carries, per consolidation_group, the entity rows and the budget's
   own layers (cta, unbalanced, nci_attribution) per (scenario_id, cycle, layer). This view rolls them
   to the group and puts the group in the entity slot the epm_batch query builder expects:

     entity  arg  -> data_area_id = consolidation_group
     account arg  -> main_account
     measure      -> consolidated_amount  (every adjustment type summed)
     scenario_id, layer                    (konsol's `consolidated_budget` Dataset binds both:
                                            has_scenario_id 1, has_layer 1; no layer = layers summed)
     cycle                                 (carried, never bound by the Dataset)

   Which Cycle: a budget-type scenario has one Cycle per year (assert_budget_one_cycle_per_scenario_year),
   so every row passes. A forecast-type scenario holds one approved Cycle per ROUND, several per year,
   and rounds never sum (konsol#348 S6-Q1 b, Deepak Pai, 17 Nov 2026): only the rows of the DECLARED
   current round (gold_forecast_current_round) are here, the filter gold_scenario_trial_balance and
   gold_forecast_current use. A forecast (scenario, year) with no declaration has no rows
   (assert_forecast_year_has_current_round WARNs naming it). IN with a tuple, not a join
   (join_use_nulls=0 fills an unmatched join with '').

   BEFORE ELIMINATIONS, like the model it reads: no ic_elimination (konsol#427), no deal journals,
   topside or equity method (konsol#425). A grain with no row reads 0 in K.EPM, as every budget Dataset
   does. Nothing here reads or is read by the close (tests/test_budget_outside_close.py).
   assert_consolidated_budget_fact_hand_table pins it on two groups, two layers and two rounds. #}

select
    consolidation_group as data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    scenario_id,
    cycle,
    layer,
    sum(coalesce(amount, 0)) as consolidated_amount
from {{ ref('gold_fully_consolidated_budget') }}
where scenario_id not in (
        select scenario_id
        from {{ source('epm_gold', 'scenario_definitions') }}
        where scenario_type = 'forecast'
    )
   or (scenario_id, toUInt16(fiscal_year), cycle) in (
        select scenario_id, toUInt16(fiscal_year), cycle
        from {{ ref('gold_forecast_current_round') }}
    )
group by
    consolidation_group,
    fiscal_year,
    fiscal_period,
    main_account,
    scenario_id,
    cycle,
    layer
