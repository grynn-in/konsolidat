{{
    config(
        engine='MergeTree()',
        order_by='(dimension_name, dimension_value)'
    )
}}

select
    {{ cast_to_string('FinancialDimensionName') }} as dimension_name,
    {{ cast_to_string('DimensionValue') }} as dimension_value,
    {{ cast_to_string("coalesce(Description, '')") }} as description,
    {{ cast_to_int8('coalesce(IsSuspended, 0)') }} as is_suspended,
    {{ cast_to_date("coalesce(ActiveFrom, '1900-01-01')") }} as active_from,
    {{ cast_to_date("coalesce(ActiveTo, '2099-12-31')") }} as active_to,
    {{ cast_to_int64('RecId') }} as recid,
    {{ cast_to_datetime('_airbyte_extracted_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_airbyte_raw_id') }} as _airbyte_raw_id
from {{ ref('stg_d365__financial_dimension_values') }}
