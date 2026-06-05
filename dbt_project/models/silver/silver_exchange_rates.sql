{{
    config(
        engine='MergeTree()',
        order_by='(from_currency, to_currency, valid_from)'
    )
}}

select
    from_currency,
    to_currency,
    valid_from,
    valid_to,
    -- D365 stores exchange rates multiplied by 100
    exchange_rate / 100.0 as exchange_rate,
    exchange_rate_type,
    recid
from {{ ref('bronze_exchange_rate_currency_pairs') }}
where exchange_rate > 0  -- Filter out bad/zero rates
