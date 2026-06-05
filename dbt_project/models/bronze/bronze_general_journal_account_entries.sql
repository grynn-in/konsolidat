{{
    config(
        engine='MergeTree()',
        order_by='(data_area_id, accounting_date, recid)',
        partition_by='toYYYYMM(accounting_date)'
    )
}}

select
    toInt64(RecId) as recid,
    toString(dataAreaId) as data_area_id,
    toDate(AccountingDate) as accounting_date,
    toString(MainAccount) as main_account,
    toDecimal128(AccountingCurrencyAmount, 2) as accounting_currency_amount,
    toDecimal128(ReportingCurrencyAmount, 2) as reporting_currency_amount,
    toDecimal128(TransactionCurrencyAmount, 2) as transaction_currency_amount,
    toString(TransactionCurrencyCode) as transaction_currency_code,
    toString(PostingType) as posting_type,
    toInt64(GeneralJournalEntry) as general_journal_entry_recid,
    toString(LedgerAccount) as ledger_account,
    toString(Text) as description,
    toString(coalesce(CostCenter, '')) as dim_cost_center,
    toString(coalesce(Department, '')) as dim_department,
    toString(coalesce(BusinessUnit, '')) as dim_business_unit,
    toInt8(IsCredit) as is_credit,
    toDateTime(_airbyte_extracted_at) as _airbyte_extracted_at,
    toString(_airbyte_raw_id) as _airbyte_raw_id
from {{ source('airbyte_raw', 'general_journal_account_entries') }}
