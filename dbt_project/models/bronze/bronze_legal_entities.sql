{{
    config(
        engine='MergeTree()',
        order_by='(data_area)'
    )
}}

select
    {{ cast_to_string('entity_id') }} as data_area,
    {{ cast_to_string('entity_name') }} as entity_name,
    {{ cast_to_string("coalesce(accounting_currency, '')") }} as accounting_currency,
    {{ cast_to_string("coalesce(reporting_currency, '')") }} as reporting_currency,
    {{ cast_to_string("coalesce(party_number, '')") }} as party_number,
    {{ cast_to_string("coalesce(country_region, '')") }} as country_region,
    {{ cast_to_datetime('_loaded_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_raw_id') }} as _airbyte_raw_id
from {{ ref('stg_legal_entities') }}
