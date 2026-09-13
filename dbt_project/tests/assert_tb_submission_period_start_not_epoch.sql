{#
    Guard against the join_use_nulls=0 default silently winning over the TBS
    coalesce fallback.

    silver_gl_entries builds a synthetic GL row for every trial-balance
    submission (F8). Its accounting_date/document_date come from a LEFT JOIN
    from bronze_trial_balance_submissions to silver_fiscal_periods, coalesced
    to build_date_from_year_period() when the entity's fiscal calendar isn't
    loaded -- exactly the shape of a TB-only site, which has no ERP calendar
    at all (konsol#182).

    Under join_use_nulls=0 ClickHouse fills an unmatched LEFT JOIN with the
    joined column's type default, NOT NULL. Date's default is toDate(0) =
    1970-01-01, so coalesce(sfp.period_start_date, ...) never falls through:
    every submission for an entity with no loaded calendar lands on
    1970-01-01 instead of the first day of its own fiscal year/period.

    This test fails if any Trial Balance Submission row in silver_gl_entries
    carries the ClickHouse Date zero-value, which is never a legitimate
    posting date for a submitted batch.
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
