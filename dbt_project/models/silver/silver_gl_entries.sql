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
    -- konsolidat#112: derive debit/credit from the SIGN of the (already-signed)
    -- accounting_currency_amount. The raw signed amount provably balances (every
    -- voucher nets to 0), so the sign is the source of truth: positive = debit,
    -- negative = credit. (abs() would discard the sign on contra/reversal lines.)
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

{# F8: submitted trial balances enter the ledger flow HERE, as one GL-shaped
   row per account. A submission is already at trial-balance grain (period
   totals per account), which is exactly what gold_trial_balance aggregates GL
   entries down to — so shaping each claimed row as a single synthetic entry
   lets every downstream model (consolidation, variance, cash flow, the
   var-driven measures) work unchanged, with no fork in the gold layer.

   Only CLAIMED batches reach bronze_trial_balance_submissions (the control-
   table join), so cancellation removes a submission from here without any
   delete. Column list and ORDER mirror the select above exactly — UNION ALL
   is positional. #}

union all

select
    toInt64(cityHash64(tbs.batch_id, tbs.main_account)) as recid,
    tbs.data_area_id as data_area_id,
    makeDate(tbs.fiscal_year, tbs.fiscal_period, 1) as accounting_date,
    tbs.fiscal_year as fiscal_year,
    tbs.fiscal_period as fiscal_period,
    tbs.main_account as main_account,
    ma.account_name as account_name,
    ma.account_type_name as account_type_name,
    ma.is_balance_sheet as is_balance_sheet,
    ma.is_pnl as is_pnl,
    tbs.debit_amount - tbs.credit_amount as accounting_currency_amount,
    tbs.debit_amount - tbs.credit_amount as reporting_currency_amount,
    tbs.debit_amount - tbs.credit_amount as transaction_currency_amount,
    '' as transaction_currency_code,
    {# a TB row carries explicit debit and credit columns — no sign derivation #}
    tbs.credit_amount as credit_amount,
    tbs.debit_amount as debit_amount,
    'Trial Balance Submission' as posting_type,
    tbs.description as description,
    {% for d in var('dimensions') %}
    '' as {{ d.name }}{{ ',' if not loop.last }}
    {%- endfor %},
    concat('TBS-', tbs.batch_id) as journal_number,
    'Trial Balance Submission' as journal_category,
    tbs.submission_name as document_number,
    makeDate(tbs.fiscal_year, tbs.fiscal_period, 1) as document_date,
    '' as posting_layer
from {{ ref('bronze_trial_balance_submissions') }} as tbs
left join {{ ref('silver_main_accounts') }} as ma
    on tbs.main_account = ma.main_account_id
