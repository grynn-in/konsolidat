{# konsol#348 S3 B8–B10 (QB3 a, decided 14 Nov 2026 under Deepak Pai's standing rule): a variance row
   compares like with like. The currency joins the variance grain, so a budget row never nets against an
   actual in another currency: a USD actual and a EUR budget on one (entity, year, period, account, dims,
   budget scenario) come out as two rows, one per currency, each with the other side missing.

   The test behind each variance model names every such grain: a (entity, year, period, account, budget
   dims, budget_scenario_id) that holds more than one currency. Upstream, assert_budget_currency_is_
   entity_currency (B7) refuses the budget line that causes it, so this is the backstop at the variance
   grain: it says where a reader would have seen a mixed-currency comparison, had the grain not carried
   the currency. One row per grain; error severity. #}
{% macro variance_single_currency_sql(model, period_column) %}
select
    data_area_id,
    fiscal_year,
    {{ period_column }},
    main_account,
    {{ dim_select(dims=get_budget_dimensions(), trailing=true) }}
    budget_scenario_id,
    groupUniqArray(currency) as currencies_on_grain,
    uniqExact(currency) as currency_count
from {{ ref(model) }}
group by
    data_area_id,
    fiscal_year,
    {{ period_column }},
    main_account,
    {{ dim_group_by(dims=get_budget_dimensions(), trailing=true) }}
    budget_scenario_id
having uniqExact(currency) > 1
{% endmacro %}
