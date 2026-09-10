{#
    D365 F&O exchange rates adapter.

    Emits TRUE rates. ConversionFactor is a D365 concept, so it is resolved
    here and nowhere else: a 'Hundred' row quotes the rate per 100 units of
    from-currency (100 EUR = 93.50 CHF -> Rate 93.50), so it is divided by 100;
    a 'One' row already holds the true rate and passes through.

    This model used to normalise everything to a x100 representation
    ('One' -> Rate*100) for silver to divide back down. That split the scaling
    across two layers with contradictory assumptions, and any data that did not
    match the contract was silently wrong by two orders of magnitude — every
    foreign subsidiary consolidated at ~1% of its value (#138). The ERPNext
    adapter emits true rates and never fit the x100 contract at all, so under
    the old scheme its rates would have been wrongly divided too.

    Output matches canonical stg_exchange_rates schema: true rates, whatever
    the ERP.
#}

select
    'd365_fo' as erp_source,
    coalesce(FromCurrency, '') as from_currency,
    coalesce(ToCurrency, '') as to_currency,
    toDate(substring(coalesce(toString(StartDate), '1900-01-01'), 1, 10)) as valid_from,
    toDate(substring(coalesce(toString(EndDate), '2099-12-31'), 1, 10)) as valid_to,
    case
        when coalesce(toString(ConversionFactor), 'One') = 'Hundred' then coalesce(Rate, 0) / 100
        else coalesce(Rate, 0)
    end as exchange_rate,
    coalesce(RateTypeName, '') as rate_type,
    _airbyte_extracted_at as _loaded_at,
    _airbyte_raw_id as _raw_id
from {{ source('d365_raw', 'exchange_rates') }}
