{# konsol#348 S3 B6 (QB3 a, decided 14 Nov 2026 under Deepak Pai's standing rule): every row of
   gold_scenario_trial_balance carries its currency.

   The scenario trial balance is where actuals and budgets meet, so each row says what currency it is in:
   the GL branch takes the entity's accounting currency (silver_entity_currencies, the one answer for the
   books an entity keeps, konsol#110); the budget branch takes the fact's (gold_spread_budget.currency,
   B4). The variance models then carry the currency on their grain (B8) and can refuse to net two
   currencies.

   The GL branch LEFT JOINs silver_entity_currencies, and join_use_nulls=0 fills an entity with no
   currency row with ''. That default is not a fallback: this test names every such row, so a trial
   balance for an entity that declares no currency (konsol#328 refuses it at intake) cannot sit in the
   scenario fact unmarked. A budget row with a blank currency is named here too, beside
   assert_budget_blank_layer_currency on the line itself.

   One row per (scenario, entity, data_source) with blank-currency rows, and their count. Error severity.
   Fixtures: dbt_project/test_fixtures/assert_scenario_tb_currency_declared*.sql. #}
{{ config(severity='error') }}

select
    scenario_id,
    data_area_id,
    data_source,
    count() as n_rows
from {{ ref('gold_scenario_trial_balance') }}
where currency = ''
group by scenario_id, data_area_id, data_source
