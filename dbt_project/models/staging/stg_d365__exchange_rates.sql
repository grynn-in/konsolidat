{#
    Exchange Rates staging model.
    Maps ExchangeRates → exchange_rate_currency_pairs.
    Scales rate × 100 when ConversionFactor='One' so dbt /100 works correctly.
#}

select
    coalesce(FromCurrency, '') as FromCurrencyCode,
    coalesce(ToCurrency, '') as ToCurrencyCode,
    StartDate as ValidFrom,
    coalesce(EndDate, toDate('2099-12-31')) as ValidTo,
    case
        when coalesce(ConversionFactor, 'One') = 'One' then coalesce(Rate, 0) * 100
        else coalesce(Rate, 0)
    end as ExchangeRate,
    coalesce(RateTypeName, '') as ExchangeRateType,
    rowNumberInAllBlocks() as RecId,
    _airbyte_extracted_at,
    _airbyte_raw_id
from {{ source('d365_raw', 'exchange_rates') }}
