{{
    config(
        engine='MergeTree()',
        order_by='(data_area)'
    )
}}

select
    data_area,
    entity_name,
    accounting_currency,
    reporting_currency,
    party_number,
    country_region
from {{ ref('bronze_legal_entities') }}
