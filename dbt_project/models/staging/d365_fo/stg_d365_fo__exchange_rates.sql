{#
    D365 F&O exchange rates adapter.
    Scales rate × 100 when ConversionFactor='One'.
    Output matches canonical stg_exchange_rates schema.
#}

select
    'd365_fo' as erp_source,
    coalesce(FromCurrency, '') as from_currency,
    coalesce(ToCurrency, '') as to_currency,
    toString(toDate(substring(coalesce(toString(StartDate), '1900-01-01'), 1, 10))) as valid_from,
    toString(toDate(substring(coalesce(toString(EndDate), '2099-12-31'), 1, 10))) as valid_to,
    toString(
        case
            when coalesce(toString(ConversionFactor), 'One') = 'One' then coalesce(Rate, 0) * 100
            else coalesce(Rate, 0)
        end
    ) as exchange_rate,
    coalesce(RateTypeName, '') as rate_type,
    toString(_airbyte_extracted_at) as _loaded_at,
    toString(_airbyte_raw_id) as _raw_id
from {{ source('d365_raw', 'ExchangeRates') }}
