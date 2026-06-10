{{
    config(
        engine='MergeTree()',
        order_by='(from_currency, to_currency, valid_from)',
        partition_by='toYear(valid_from)'
    )
}}

select
    {{ cast_to_string('from_currency') }} as from_currency,
    {{ cast_to_string('to_currency') }} as to_currency,
    {{ cast_to_date('valid_from') }} as valid_from,
    {{ cast_to_date("coalesce(valid_to, '2099-12-31')") }} as valid_to,
    {{ cast_to_decimal128('exchange_rate', 6) }} as exchange_rate,
    {{ cast_to_string("coalesce(rate_type, '')") }} as exchange_rate_type,
    rowNumberInAllBlocks() as recid,
    {{ cast_to_datetime('_loaded_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_raw_id') }} as _airbyte_raw_id
from {{ ref('stg_exchange_rates') }}
