{#
    D365 F&O legal entities adapter.
    Joins LegalEntities with Ledgers for currency info.
    Output matches canonical stg_legal_entities schema.
#}

with entities as (
    select * from {{ source('d365_raw', 'legal_entities') }}
),

ledgers as (
    select * from {{ source('d365_raw', 'ledgers') }}
),

joined as (
    select
        'd365_fo' as erp_source,
        entities.LegalEntityId as entity_id,
        coalesce(entities.Name, '') as entity_name,
        coalesce(ledgers.AccountingCurrency, '') as accounting_currency,
        coalesce(ledgers.ReportingCurrency, '') as reporting_currency,
        coalesce(entities.PartyNumber, '') as party_number,
        coalesce(entities.AddressCountryRegionId, '') as country_region,
        entities._airbyte_extracted_at as _loaded_at,
        entities._airbyte_raw_id as _raw_id
    from entities
    left join ledgers
        on lower(entities.LegalEntityId) = lower(ledgers.LegalEntityId)
)

select * from joined
