{{
    config(
        engine='MergeTree()',
        order_by='(data_area_id, transaction_date, main_account)'
    )
}}

{# Date-level fiscal lookup for ClickHouse (no range joins). konsol#348 (A12): the declared Regular periods
   of konsol's fiscal calendar, since silver_fiscal_periods (the ERP calendar) is removed. This model reads the
   ERP budget tables and leaves with them in stage B (B2). #}
with fiscal_dates as (
    select
        {{ cast_to_date('arrayJoin(arrayMap(x -> addDays(start_date, x), range(toUInt32(dateDiff(\'day\', start_date, end_date) + 1))))') }} as calendar_date,
        toUInt16(fiscal_year) as fiscal_year,
        toUInt16(fiscal_period) as fiscal_period
    from {{ source('epm_staging', 'fiscal_periods') }}
    where period_type = 'Regular'
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
