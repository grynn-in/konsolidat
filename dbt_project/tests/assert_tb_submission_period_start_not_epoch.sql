{#
    A trial-balance submission row in silver_gl_entries dated 1970-01-01.

    silver_gl_entries builds a synthetic GL row for every trial-balance
    submission (F8), dated at the declared start_date of its period
    (declared_periods(), konsol's fiscal calendar; konsol#348). A period the
    calendar does not declare misses that LEFT JOIN, and under
    join_use_nulls=0 ClickHouse fills Date's default, toDate(0) = 1970-01-01,
    not NULL. The row is kept, not dated by a guess, and this test names it.
    (Before konsol#348 the date came from the ERP calendar, silver_fiscal_periods,
    with a calendar-month fallback, and the epoch was the coalesce trap.)

    Fails if any Trial Balance Submission row carries the Date zero-value,
    which is never a legitimate posting date for a submitted batch.
    Fixture: test_fixtures/assert_tb_submission_period_start_not_epoch.undeclared.must_flag.sql.
#}
select
    data_area_id,
    fiscal_year,
    fiscal_period,
    document_number,
    accounting_date
from {{ ref('silver_gl_entries') }}
where posting_type = 'Trial Balance Submission'
  and accounting_date = toDate(0)
