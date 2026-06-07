{#
    Legal Entities staging model.
    Joins LegalEntities with Ledgers to get AccountingCurrency and ReportingCurrency.
#}

with entities as (
    select * from {{ source('d365_raw', 'LegalEntities') }}
),

ledgers as (
    select * from {{ source('d365_raw', 'Ledgers') }}
),

joined as (
    select
        entities.LegalEntityId as dataArea,
        coalesce(entities.Name, '') as Name,
        coalesce(ledgers.AccountingCurrency, '') as AccountingCurrency,
        coalesce(ledgers.ReportingCurrency, '') as ReportingCurrency,
        coalesce(entities.PartyNumber, '') as PartyNumber,
        coalesce(entities.AddressCountryRegionId, '') as AddressCountryRegionId,
        entities._airbyte_extracted_at,
        entities._airbyte_raw_id
    from entities
    left join ledgers
        on lower(entities.LegalEntityId) = lower(ledgers.LegalEntityId)
)

select * from joined
