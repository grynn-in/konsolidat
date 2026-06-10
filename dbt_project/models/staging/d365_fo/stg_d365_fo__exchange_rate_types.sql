{#
    Exchange Rate Types staging model.
    Maps Name → ExchangeRateType.
#}

select
    coalesce(Name, '') as ExchangeRateType,
    coalesce(Name, '') as Name,
    coalesce(Description, '') as Description,
    rowNumberInAllBlocks() as RecId,
    _airbyte_extracted_at,
    _airbyte_raw_id
from {{ source('d365_raw', 'ExchangeRateTypes') }}
