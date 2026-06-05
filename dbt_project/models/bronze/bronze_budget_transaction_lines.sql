{{
    config(
        engine='MergeTree()',
        order_by='(budget_register_entry_recid, recid)',
        partition_by='toYYYYMM(transaction_date)'
    )
}}

select
    toInt64(RecId) as recid,
    toInt64(BudgetRegisterEntry) as budget_register_entry_recid,
    toDate(Date) as transaction_date,
    toString(MainAccount) as main_account,
    toDecimal128(AccountingCurrencyAmount, 2) as accounting_currency_amount,
    toDecimal128(TransactionCurrencyAmount, 2) as transaction_currency_amount,
    toString(coalesce(TransactionCurrency, '')) as transaction_currency,
    toString(coalesce(CostCenter, '')) as dim_cost_center,
    toString(coalesce(Department, '')) as dim_department,
    toInt8(coalesce(IncludeInCashFlowForecast, 0)) as include_in_cash_flow,
    toDateTime(_airbyte_extracted_at) as _airbyte_extracted_at,
    toString(_airbyte_raw_id) as _airbyte_raw_id
from {{ source('airbyte_raw', 'budget_transaction_lines') }}
