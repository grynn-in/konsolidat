{# konsol#348 S3 B9 (QB3 a): gold_variance_ytd compares like with like. Every (entity, year, period, account,
   budget dims, budget_scenario_id) running total holds one currency; a grain in two means a budget line in a
   currency other than the entity's actuals, which B7 (assert_budget_currency_is_entity_currency) refuses
   upstream. The rule and its reasons: macros/variance_single_currency.sql.
   Fixtures: dbt_project/test_fixtures/variance_budget_scenario.sql (pass),
   variance_currency_mismatch.must_flag.sql (flag). #}
{{ config(severity='error') }}

{{ variance_single_currency_sql('gold_variance_ytd', 'fiscal_period') }}
