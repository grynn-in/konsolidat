{{
    config(
        engine='MergeTree()',
        order_by='(data_area_id, fiscal_year, main_account)',
        partition_by='fiscal_year'
    )
}}

select
    toString(dataAreaId) as data_area_id,
    toString(MainAccount) as main_account,
    toString(coalesce(MainAccountName, '')) as main_account_name,
    toUInt16(FiscalYear) as fiscal_year,
    toDecimal128(coalesce(OpeningBalance, 0), 2) as opening_balance,
    toDecimal128(coalesce(DebitAmount, 0), 2) as debit_amount,
    toDecimal128(coalesce(CreditAmount, 0), 2) as credit_amount,
    toDecimal128(coalesce(ClosingBalance, 0), 2) as closing_balance,
    toString(coalesce(CurrencyCode, '')) as currency_code,
    toString(coalesce(AccountType, '')) as account_type,
    toDateTime(_airbyte_extracted_at) as _airbyte_extracted_at,
    toString(_airbyte_raw_id) as _airbyte_raw_id
from {{ source('airbyte_raw', 'trial_balance_snapshot') }}
