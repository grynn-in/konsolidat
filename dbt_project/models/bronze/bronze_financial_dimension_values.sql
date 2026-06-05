{{
    config(
        engine='MergeTree()',
        order_by='(dimension_name, dimension_value)'
    )
}}

select
    toString(FinancialDimensionName) as dimension_name,
    toString(DimensionValue) as dimension_value,
    toString(coalesce(Description, '')) as description,
    toInt8(coalesce(IsSuspended, 0)) as is_suspended,
    toDate(coalesce(ActiveFrom, '1900-01-01')) as active_from,
    toDate(coalesce(ActiveTo, '2099-12-31')) as active_to,
    toInt64(RecId) as recid,
    toDateTime(_airbyte_extracted_at) as _airbyte_extracted_at,
    toString(_airbyte_raw_id) as _airbyte_raw_id
from {{ source('airbyte_raw', 'financial_dimension_values') }}
