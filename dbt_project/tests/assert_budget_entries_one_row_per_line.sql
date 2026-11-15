{# konsol#348 PR3 (A12; PR #360 review, finding 5): silver_budget_entries carries exactly one row per ERP budget
   line (recid).

   The model puts a line in the declared Regular period that holds its transaction_date through a date spine
   arrayJoined from epm_staging.fiscal_periods. The spine must hold each date once: a period declared on two
   rows (a calendar loaded twice) must be grouped to one (fiscal_year, fiscal_period) before its dates are
   spun out, as declared_periods() does. Spun out ungrouped, every date of that period appears twice and every
   budget line dated in it comes out twice: the budget doubles with no error. This test fails the build on any
   line with more than one row.

   One row per duplicated recid. Error severity: a doubled budget is a wrong number.
   Fixtures: dbt_project/test_fixtures/assert_budget_entries_one_row_per_line*.sql. #}
{{ config(severity='error') }}

select
    recid,
    any(data_area_id) as data_area_id,
    any(transaction_date) as transaction_date,
    count() as n_rows,
    'more than one row for one budget line' as fault
from {{ ref('silver_budget_entries') }}
group by recid
having count() > 1
