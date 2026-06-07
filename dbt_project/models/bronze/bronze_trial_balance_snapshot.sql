{{
    config(
        engine='MergeTree()',
        order_by='(data_area_id, fiscal_year, main_account)',
        partition_by='fiscal_year'
    )
}}

select
    {{ cast_to_string('dataAreaId') }} as data_area_id,
    {{ cast_to_string('MainAccount') }} as main_account,
    {{ cast_to_string("coalesce(MainAccountName, '')") }} as main_account_name,
    {{ cast_to_uint16('FiscalYear') }} as fiscal_year,
    {{ cast_to_decimal128('coalesce(OpeningBalance, 0)', 2) }} as opening_balance,
    {{ cast_to_decimal128('coalesce(DebitAmount, 0)', 2) }} as debit_amount,
    {{ cast_to_decimal128('coalesce(CreditAmount, 0)', 2) }} as credit_amount,
    {{ cast_to_decimal128('coalesce(ClosingBalance, 0)', 2) }} as closing_balance,
    {{ cast_to_string("coalesce(CurrencyCode, '')") }} as currency_code,
    {{ cast_to_string("coalesce(AccountType, '')") }} as account_type,
    {{ cast_to_datetime('_airbyte_extracted_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_airbyte_raw_id') }} as _airbyte_raw_id
from {{ ref('stg_d365__trial_balance') }}
