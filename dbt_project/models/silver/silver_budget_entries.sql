{{
    config(
        engine='MergeTree()',
        order_by='(data_area_id, transaction_date, main_account)'
    )
}}

{# Date-level fiscal lookup for ClickHouse (no range joins) #}
with fiscal_dates as (
    select
        {{ cast_to_date('arrayJoin(arrayMap(x -> addDays(period_start_date, x), range(toUInt32(dateDiff(\'day\', period_start_date, period_end_date) + 1))))') }} as calendar_date,
        {{ extract_year('year_start_date') }} as fiscal_year,
        calendar_month as fiscal_period
    from {{ ref('silver_fiscal_periods') }}
)

select
    btl.recid,
    bre.data_area_id,
    btl.transaction_date,
    coalesce(fp.fiscal_year, {{ extract_year('btl.transaction_date') }}) as fiscal_year,
    coalesce(fp.fiscal_period, {{ extract_month('btl.transaction_date') }}) as fiscal_period,
    btl.main_account,
    btl.accounting_currency_amount,
    btl.transaction_currency_amount,
    btl.transaction_currency,
    {{ dim_select(prefix='btl.', dims=get_budget_dimensions()) }},
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
