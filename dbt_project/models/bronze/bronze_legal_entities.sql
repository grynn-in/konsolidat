{{
    config(
        engine='MergeTree()',
        order_by='(data_area)'
    )
}}

select
    {{ cast_to_string('dataArea') }} as data_area,
    {{ cast_to_string('Name') }} as entity_name,
    {{ cast_to_string("coalesce(AccountingCurrency, '')") }} as accounting_currency,
    {{ cast_to_string("coalesce(ReportingCurrency, '')") }} as reporting_currency,
    {{ cast_to_string("coalesce(PartyNumber, '')") }} as party_number,
    {{ cast_to_string("coalesce(AddressCountryRegionId, '')") }} as country_region,
    {{ cast_to_datetime('_airbyte_extracted_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_airbyte_raw_id') }} as _airbyte_raw_id
from {{ source('airbyte_raw', 'legal_entities') }}
