{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# Build a date-keyed fiscal lookup: one row per calendar date with fiscal_year/period.
   ClickHouse doesn't support range joins or correlated subqueries, so we pre-expand
   the fiscal calendar into a date-level lookup table. #}
with fiscal_dates as (
    select
        calendar_id,
        {{ cast_to_date('arrayJoin(arrayMap(x -> addDays(period_start_date, x), range(toUInt32(dateDiff(\'day\', period_start_date, period_end_date) + 1))))') }} as calendar_date,
        {{ extract_year('year_start_date') }} as fiscal_year,
        calendar_month as fiscal_period
    from {{ ref('silver_fiscal_periods') }}
)

select
    gae.recid as recid,
    gae.data_area_id as data_area_id,
    gae.accounting_date as accounting_date,
    {# ClickHouse LEFT JOIN fills an unmatched fp row with the column default
       (0 for UInt), NOT NULL — so coalesce() never falls through. When the
       entity's fiscal calendar isn't present in silver_fiscal_periods (e.g. the
       seed maps entities to 'Fiscal' but only 'Standard' is loaded), fp.* is 0;
       derive the period from accounting_date in that case. #}
    if(fp.fiscal_year != 0, fp.fiscal_year, {{ extract_year('gae.accounting_date') }}) as fiscal_year,
    if(fp.fiscal_period != 0, fp.fiscal_period, {{ extract_month('gae.accounting_date') }}) as fiscal_period,
    gae.main_account as main_account,
    ma.account_name as account_name,
    ma.account_type_name as account_type_name,
    ma.is_balance_sheet as is_balance_sheet,
    ma.is_pnl as is_pnl,
    gae.accounting_currency_amount as accounting_currency_amount,
    gae.reporting_currency_amount as reporting_currency_amount,
    gae.transaction_currency_amount as transaction_currency_amount,
    gae.transaction_currency_code as transaction_currency_code,
    -- konsolidat: derive debit/credit from the SIGN of the (already-signed)
    -- accounting_currency_amount, not from is_credit. D365 ships IsCredit as a
    -- JSON-quoted string ("Yes"/"No") that the staging parser misses, so
    -- is_credit is ~always 0 (every line booked as a debit) — and abs() then
    -- discards the real sign on contra/reversal lines too. The raw signed
    -- amount provably balances (every voucher nets to 0), so the sign is the
    -- source of truth: positive = debit, negative = credit.
    case
        when gae.accounting_currency_amount < 0 then -gae.accounting_currency_amount
        else 0
    end as credit_amount,
    case
        when gae.accounting_currency_amount > 0 then gae.accounting_currency_amount
        else 0
    end as debit_amount,
    gae.posting_type as posting_type,
    gae.description as description,
    {{ dim_select(prefix='gae.') }},
    gje.journal_number as journal_number,
    gje.journal_category as journal_category,
    gje.document_number as document_number,
    gje.document_date as document_date,
    gje.posting_layer as posting_layer
from {{ ref('bronze_general_journal_account_entries') }} as gae
left join {{ ref('bronze_general_journal_entries') }} as gje
    on gae.general_journal_entry_recid = gje.recid
    and gae.data_area_id = gje.data_area_id
left join {{ ref('silver_main_accounts') }} as ma
    on gae.main_account = ma.main_account_id
left join {{ ref('entity_fiscal_calendars') }} as efc
    on gae.data_area_id = efc.data_area_id
left join fiscal_dates as fp
    on gae.accounting_date = fp.calendar_date
    and fp.calendar_id = coalesce(efc.fiscal_calendar_id, 'Fiscal')
