{{
    config(
        engine='MergeTree()',
        order_by='(data_area_id, accounting_date, recid)',
        partition_by='toYYYYMM(accounting_date)'
    )
}}

select
    gae.recid,
    gae.data_area_id,
    gae.accounting_date,
    toYear(gae.accounting_date) as fiscal_year,
    toMonth(gae.accounting_date) as fiscal_period,
    gae.main_account,
    ma.account_name,
    ma.account_type_name,
    ma.is_balance_sheet,
    ma.is_pnl,
    gae.accounting_currency_amount,
    gae.reporting_currency_amount,
    gae.transaction_currency_amount,
    gae.transaction_currency_code,
    case
        when gae.is_credit = 1 then gae.accounting_currency_amount
        else 0
    end as credit_amount,
    case
        when gae.is_credit = 0 then gae.accounting_currency_amount
        else 0
    end as debit_amount,
    gae.posting_type,
    gae.description,
    gae.dim_cost_center,
    gae.dim_department,
    gae.dim_business_unit,
    gje.journal_number,
    gje.journal_category,
    gje.document_number,
    gje.document_date,
    gje.posting_layer
from {{ ref('bronze_general_journal_account_entries') }} as gae
left join {{ ref('bronze_general_journal_entries') }} as gje
    on gae.general_journal_entry_recid = gje.recid
    and gae.data_area_id = gje.data_area_id
left join {{ ref('silver_main_accounts') }} as ma
    on gae.main_account = ma.main_account_id
