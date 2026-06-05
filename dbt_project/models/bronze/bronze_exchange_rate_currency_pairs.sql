{{
    config(
        engine='MergeTree()',
        order_by='(from_currency, to_currency, valid_from)',
        partition_by='toYYYYMM(valid_from)'
    )
}}

select
    toString(FromCurrencyCode) as from_currency,
    toString(ToCurrencyCode) as to_currency,
    toDate(ValidFrom) as valid_from,
    toDate(coalesce(ValidTo, '2099-12-31')) as valid_to,
    toDecimal128(ExchangeRate, 6) as exchange_rate,
    toString(coalesce(ExchangeRateType, '')) as exchange_rate_type,
    toInt64(RecId) as recid,
    toDateTime(_airbyte_extracted_at) as _airbyte_extracted_at,
    toString(_airbyte_raw_id) as _airbyte_raw_id
from {{ source('airbyte_raw', 'exchange_rate_currency_pairs') }}
