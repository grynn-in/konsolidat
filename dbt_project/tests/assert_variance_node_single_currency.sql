{# konsol#348 S3 B11 (QB3 a): gold_variance_at_hierarchy_node carries the currency of gold_variance_analysis
   (B8) through the rollup and groups by it, so a node never sums amounts in two currencies. Every (hierarchy,
   node, entity, year, period, account, budget dims, budget_scenario_id) holds one currency; a node in two
   means a budget line in a currency other than the entity's actuals, which B7
   (assert_budget_currency_is_entity_currency) refuses upstream and assert_variance_single_currency names at
   the variance grain. One row per node key in two currencies; error severity.
   Fixtures: dbt_project/test_fixtures/variance_node_two_budgets.sql (pass),
   variance_node_currency_mismatch.must_flag.sql (flag). #}
{{ config(severity='error') }}

select
    hierarchy_name,
    hierarchy_dimension,
    hierarchy_member_code,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    {{ dim_select(dims=get_budget_dimensions(), trailing=true) }}
    budget_scenario_id,
    groupUniqArray(currency) as currencies_on_node,
    uniqExact(currency) as currency_count
from {{ ref('gold_variance_at_hierarchy_node') }}
group by
    hierarchy_name,
    hierarchy_dimension,
    hierarchy_member_code,
    data_area_id,
    fiscal_year,
    fiscal_period,
    main_account,
    {{ dim_group_by(dims=get_budget_dimensions(), trailing=true) }}
    budget_scenario_id
having uniqExact(currency) > 1
