{{
    config(
        engine='MergeTree()',
        order_by='(exchange_rate_type)'
    )
}}

select
    {{ cast_to_string('ExchangeRateType') }} as exchange_rate_type,
    {{ cast_to_string("coalesce(Name, '')") }} as type_name,
    {{ cast_to_string("coalesce(Description, '')") }} as description,
    {{ cast_to_int64('RecId') }} as recid,
    {{ cast_to_datetime('_airbyte_extracted_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_airbyte_raw_id') }} as _airbyte_raw_id
from {{ ref('stg_d365__exchange_rate_types') }}
