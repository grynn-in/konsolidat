{#
    D365 F&O exchange rates adapter — emits TRUE rates.

    ConversionFactor is a D365 concept (a 'Hundred' row quotes the rate per 100
    units of from-currency: 100 EUR = 93.50 CHF -> Rate 93.50), so it is
    resolved here and nowhere else. No layer after staging may scale a rate;
    silver holds true rates whatever the ERP. History and why: #138.
#}

select
    'd365_fo' as erp_source,
    coalesce(FromCurrency, '') as from_currency,
    coalesce(ToCurrency, '') as to_currency,
    toDate(substring(coalesce(toString(StartDate), '1900-01-01'), 1, 10)) as valid_from,
    toDate(substring(coalesce(toString(EndDate), '2099-12-31'), 1, 10)) as valid_to,
    -- Full D365 ExchangeRateDisplayFactor enum. An unrecognised value passes
    -- through untouched — assert_conversion_factor_known fails the build on any
    -- such row, so a new enum member becomes a loud test failure, never a
    -- silently unscaled rate.
    multiIf(
        coalesce(toString(ConversionFactor), 'One') = 'Ten',         coalesce(Rate, 0) / 10,
        coalesce(toString(ConversionFactor), 'One') = 'Hundred',     coalesce(Rate, 0) / 100,
        coalesce(toString(ConversionFactor), 'One') = 'Thousand',    coalesce(Rate, 0) / 1000,
        coalesce(toString(ConversionFactor), 'One') = 'TenThousand', coalesce(Rate, 0) / 10000,
        coalesce(Rate, 0)
    ) as exchange_rate,
    coalesce(RateTypeName, '') as rate_type,
    _airbyte_extracted_at as _loaded_at,
    _airbyte_raw_id as _raw_id
from {{ source('d365_raw', 'exchange_rates') }}
