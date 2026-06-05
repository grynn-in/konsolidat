{{
    config(
        engine='MergeTree()',
        order_by='(from_currency, to_currency, valid_from)',
        partition_by='toYYYYMM(valid_from)'
    )
}}

select
    {{ cast_to_string('FromCurrencyCode') }} as from_currency,
    {{ cast_to_string('ToCurrencyCode') }} as to_currency,
    {{ cast_to_date('ValidFrom') }} as valid_from,
    {{ cast_to_date("coalesce(ValidTo, '2099-12-31')") }} as valid_to,
    {{ cast_to_decimal128('ExchangeRate', 6) }} as exchange_rate,
    {{ cast_to_string("coalesce(ExchangeRateType, '')") }} as exchange_rate_type,
    {{ cast_to_int64('RecId') }} as recid,
    {{ cast_to_datetime('_airbyte_extracted_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_airbyte_raw_id') }} as _airbyte_raw_id
from {{ source('airbyte_raw', 'exchange_rate_currency_pairs') }}
