{# konsolidat#189 PR3 (konsol#348, QA1 c / A10): a trial-balance submission row in silver_gl_entries is dated at
   the start_date its period declares in konsol's fiscal calendar (epm_staging.fiscal_periods).

   silver_gl_entries used to date a submission row from the entity's own ERP calendar and, when that was not
   loaded, at the first day of the CALENDAR month the period number names (build_date_from_year_period). An
   April-March site's FY2026 P1 is 2025-04-01; the macro made it 2026-01-01. The declared calendar is the one
   source of period dates (macros/declared_periods.sql), so the row's accounting_date is that period's
   start_date, and this test fails the build when it is not.

   One row per (entity, period) whose submission rows carry a date other than the declared start_date. A period
   the calendar does not declare has no declared date and is not judged here
   (assert_trial_balance_period_declared refuses it).
   Fixture: dbt_project/test_fixtures/assert_tb_submission_date_is_declared.sql. #}
select
    g.data_area_id as data_area_id,
    g.fiscal_year as fiscal_year,
    g.fiscal_period as fiscal_period,
    dp.start_date as declared_start_date,
    min(g.accounting_date) as accounting_date,
    count() as n_rows
from {{ ref('silver_gl_entries') }} as g
inner join {{ declared_periods() }} as dp
    on dp.fiscal_year = toUInt16(g.fiscal_year)
    and dp.fiscal_period = toUInt16(g.fiscal_period)
where g.posting_type = 'Trial Balance Submission'
  and g.accounting_date != dp.start_date
group by g.data_area_id, g.fiscal_year, g.fiscal_period, dp.start_date
