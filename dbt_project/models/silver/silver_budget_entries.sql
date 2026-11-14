{{
    config(
        engine='MergeTree()',
        order_by='(data_area_id, transaction_date, main_account)'
    )
}}

{# Date-level fiscal lookup for ClickHouse (no range joins). konsol#348 (A12): the declared Regular periods
   of konsol's fiscal calendar, since silver_fiscal_periods (the ERP calendar) is removed. This model reads the
   ERP budget tables and leaves with them in stage B (B2).

   PR #360 review, finding 5: the calendar is grouped to one row per (fiscal_year, fiscal_period) BEFORE its
   dates are spun out (min start_date, max end_date, as declared_periods() does). Spun out from the raw rows, a
   period declared twice put every one of its dates on the spine twice, and each budget line dated in it came
   out twice. assert_budget_entries_one_row_per_line (ERROR) names a line that still does. #}
with declared_regular as (
    select
        toUInt16(fiscal_year) as fiscal_year,
        toUInt16(fiscal_period) as fiscal_period,
        min(start_date) as start_date,
        max(end_date) as end_date
    from {{ source('epm_staging', 'fiscal_periods') }}
    where period_type = 'Regular'
    group by fiscal_year, fiscal_period
),

fiscal_dates as (
    select
        {{ cast_to_date('arrayJoin(arrayMap(x -> addDays(start_date, x), range(toUInt32(dateDiff(\'day\', start_date, end_date) + 1))))') }} as calendar_date,
        fiscal_year,
        fiscal_period
    from declared_regular
)

select
    {# aliased: a qualified column with no alias is named `btl.recid` in ClickHouse (PR #360 review, finding 5) #}
    btl.recid as recid,
    bre.data_area_id,
    btl.transaction_date,
    coalesce(fp.fiscal_year, {{ extract_year('btl.transaction_date') }}) as fiscal_year,
    coalesce(fp.fiscal_period, {{ extract_month('btl.transaction_date') }}) as fiscal_period,
    btl.main_account,
    btl.accounting_currency_amount,
    btl.transaction_currency_amount,
    btl.transaction_currency,
    {{ dim_select(prefix='btl.', dims=get_budget_dimensions(), trailing=true) }}
    bre.budget_model_id,
    bre.budget_transaction_code,
    bre.budget_status,
    bre.document_date as register_date,
    btl.include_in_cash_flow
from {{ ref('bronze_budget_transaction_lines') }} as btl
inner join {{ ref('bronze_budget_register_entries') }} as bre
    on btl.budget_register_entry_recid = bre.recid
left join fiscal_dates as fp
    on btl.transaction_date = fp.calendar_date
where bre.budget_status in ('Completed', 'Approved', '2', '3')  -- Only posted budgets
