{# konsol#348 S3 B7 (QB3 a, decided 14 Nov 2026 under Deepak Pai's standing rule): a budget line is in its
   entity's accounting currency.

   konsol refuses an Annual Input or a Budget Entry line whose currency is not the entity's Functional
   Currency; this is the warehouse backstop. The budget fact carries each line's currency (B4), and
   silver_entity_currencies is the one answer for the currency an entity keeps its books in (konsol#110).
   Every fact row whose currency differs from its entity's is named, so a budget can never meet actuals in
   another currency in the variance models (B8) without being reported first.

   LEFT JOIN on purpose: join_use_nulls=0 fills an entity with no currency row with '', and that is itself
   the fault named here (a budget on an entity that declares no currency), so the default hides nothing.
   A blank fact currency against a blank entity currency is not named here;
   assert_budget_blank_layer_currency names the blank line.

   One row per (scenario, cycle, entity, layer, budget currency), with the entity's currency and the row
   count. Error severity: the budget fact would be wrong.
   Fixtures: dbt_project/test_fixtures/assert_budget_currency_is_entity_currency*.sql. #}
{{ config(severity='error') }}

select
    b.scenario_id as scenario_id,
    b.cycle as cycle,
    b.data_area_id as data_area_id,
    b.layer as layer,
    b.currency as budget_currency,
    e.accounting_currency as entity_currency,
    count() as n_rows
from {{ ref('gold_spread_budget') }} as b
left join {{ ref('silver_entity_currencies') }} as e
    on e.data_area_id = b.data_area_id
where b.currency != e.accounting_currency
group by
    b.scenario_id,
    b.cycle,
    b.data_area_id,
    b.layer,
    b.currency,
    e.accounting_currency
