{{
    config(
        engine='MergeTree()',
        order_by='(data_area)'
    )
}}

select
    toString(dataArea) as data_area,
    toString(Name) as entity_name,
    toString(coalesce(AccountingCurrency, '')) as accounting_currency,
    toString(coalesce(ReportingCurrency, '')) as reporting_currency,
    toString(coalesce(PartyNumber, '')) as party_number,
    toString(coalesce(AddressCountryRegionId, '')) as country_region,
    toDateTime(_airbyte_extracted_at) as _airbyte_extracted_at,
    toString(_airbyte_raw_id) as _airbyte_raw_id
from {{ source('airbyte_raw', 'legal_entities') }}
