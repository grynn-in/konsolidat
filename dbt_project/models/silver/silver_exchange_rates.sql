{{
    config(
        engine='MergeTree()',
        order_by='(from_currency, to_currency, valid_from)'
    )
}}

with direct as (
    select
        from_currency,
        to_currency,
        valid_from,
        valid_to,
        -- Rates arrive TRUE from staging. The D365 adapter resolves
        -- ConversionFactor at the source (#138); the ERPNext adapter always
        -- emitted true rates. Silver must not scale — the old unconditional
        -- /100 here, on top of staging's conditional x100, made every
        -- 'Hundred'-tagged rate (and every ERPNext rate) wrong by two orders
        -- of magnitude.
        -- toFloat64: the old /100.0 made this Float64 as a side effect, and the
        -- inverse CTE below (1.0 / rate) is Float64 — keep the UNION's type
        -- explicit instead of relying on arithmetic accidents.
        toFloat64(exchange_rate) as exchange_rate,
        exchange_rate_type,
        recid
    from {{ ref('bronze_exchange_rate_currency_pairs') }}
    where exchange_rate > 0  -- Filter out bad/zero rates
),

-- konsolidat#106: D365 publishes only one direction (e.g. USD->JPY, never
-- JPY->USD), so cross-currency translation that needs the inverse pair misses
-- and collapses to 0. Synthesize the reciprocal rate for every quoted pair.
inverse as (
    select
        d.to_currency as from_currency,
        d.from_currency as to_currency,
        d.valid_from as valid_from,
        d.valid_to as valid_to,
        1.0 / d.exchange_rate as exchange_rate,
        d.exchange_rate_type as exchange_rate_type,
        -toInt64(d.recid) - 1 as recid  -- distinct recid (bronze recid starts at 0, so offset by 1); avoid collision with the direct row
    from direct as d
    where d.from_currency != d.to_currency
)

select from_currency, to_currency, valid_from, valid_to, exchange_rate, exchange_rate_type, toInt64(recid) as recid
from direct

union all

-- only add an inverse where no directly-quoted rate already exists for that
-- from/to/as-of/type (don't override real quotes)
select i.from_currency, i.to_currency, i.valid_from, i.valid_to, i.exchange_rate, i.exchange_rate_type, i.recid
from inverse as i
left anti join direct as d
    on i.from_currency = d.from_currency
    and i.to_currency = d.to_currency
    and i.valid_from = d.valid_from
    and i.exchange_rate_type = d.exchange_rate_type
