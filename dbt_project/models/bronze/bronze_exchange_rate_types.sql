{{
    config(
        engine='MergeTree()',
        order_by='(exchange_rate_type)'
    )
}}

select
    toString(ExchangeRateType) as exchange_rate_type,
    toString(coalesce(Name, '')) as type_name,
    toString(coalesce(Description, '')) as description,
    toInt64(RecId) as recid,
    toDateTime(_airbyte_extracted_at) as _airbyte_extracted_at,
    toString(_airbyte_raw_id) as _airbyte_raw_id
from {{ source('airbyte_raw', 'exchange_rate_types') }}
