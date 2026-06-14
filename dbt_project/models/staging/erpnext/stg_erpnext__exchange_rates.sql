{#
    ERPNext exchange rates adapter.
    Maps the `Currency Exchange` doctype → canonical stg_exchange_rates schema.

    ERPNext rates are point-in-time (a single `date`, no validity range), so
    valid_to is set to an open-ended sentinel matching the D365 adapter's
    default. ERPNext has no rate-type concept, so rate_type is empty.
#}

select
    'erpnext' as erp_source,
    coalesce(from_currency, '') as from_currency,
    coalesce(to_currency, '') as to_currency,
    toDate(substring(coalesce(toString(date), '1900-01-01'), 1, 10)) as valid_from,
    toDate('2099-12-31') as valid_to,
    coalesce(exchange_rate, 0) as exchange_rate,
    '' as rate_type,
    _airbyte_extracted_at as _loaded_at,
    _airbyte_raw_id as _raw_id
from {{ source('erpnext_raw', 'currency_exchange') }}
