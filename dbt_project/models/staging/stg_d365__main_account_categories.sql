{#
    Main Account Categories staging model.
    Maps ReferenceId → RecId, MainAccountCategory → AccountCategory,
    MainAccountType → AccountType, Closed → IsClosed.
#}

select
    coalesce(toString(ReferenceId), '0') as RecId,
    coalesce(MainAccountCategory, '') as AccountCategory,
    coalesce(Description, '') as Description,
    coalesce(MainAccountType, '') as AccountType,
    coalesce(Closed, '') as IsClosed,
    _airbyte_extracted_at,
    _airbyte_raw_id
from {{ source('d365_raw', 'MainAccountCategories') }}
