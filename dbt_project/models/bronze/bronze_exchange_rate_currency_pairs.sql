{{
    config(
        engine='MergeTree()',
        order_by='(from_currency, to_currency, valid_from)',
        partition_by='toYear(valid_from)'
    )
}}

select
    {{ cast_to_string('from_currency') }} as from_currency,
    {{ cast_to_string('to_currency') }} as to_currency,
    {{ cast_to_date('valid_from') }} as valid_from,
    {{ cast_to_date("coalesce(valid_to, '2099-12-31')") }} as valid_to,
    {# scale 12, not 6: staging now emits TRUE rates (#138), so a per-100 JPY-class
   quote arrives as ~0.0067 and a per-10000 one as ~0.0000067 — at scale 6 those
   keep 1-4 significant digits and anything under 5e-7 rounds to 0, which
   silver's `where exchange_rate > 0` would then silently drop. #}
    {{ cast_to_decimal128('exchange_rate', 12) }} as exchange_rate,
    {{ cast_to_string("coalesce(rate_type, '')") }} as exchange_rate_type,
    rowNumberInAllBlocks() as recid,
    {{ cast_to_datetime('_loaded_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_raw_id') }} as _airbyte_raw_id
from {{ ref('stg_exchange_rates') }}
