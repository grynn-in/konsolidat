{# konsol#348 S3 B10 (QB3 a): gold_variance_quarterly compares like with like. Every (entity, year, quarter,
   account, budget dims, budget_scenario_id) grain holds one currency; a grain in two means a budget line in a
   currency other than the entity's actuals, which B7 (assert_budget_currency_is_entity_currency) refuses
   upstream. The rule and its reasons: macros/variance_single_currency.sql.
   Fixtures: dbt_project/test_fixtures/variance_budget_scenario.sql (pass),
   variance_currency_mismatch.must_flag.sql (flag). #}
{{ config(severity='error') }}

{{ variance_single_currency_sql('gold_variance_quarterly', 'fiscal_quarter') }}
