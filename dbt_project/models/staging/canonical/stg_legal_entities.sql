{#
    Canonical legal entities — UNION ALL from per-ERP adapters.
    With no ERP listed in `erp_sources`, an empty relation with the same
    columns and types (empty_relation, macros/erp_sources.sql).
#}

{% set erp_sources = var('erp_sources', []) %}

{% if erp_sources | length == 0 %}
{{ empty_relation([
    ('erp_source', 'String'),
    ('entity_id', 'Nullable(String)'),
    ('entity_name', 'String'),
    ('accounting_currency', 'String'),
    ('reporting_currency', 'String'),
    ('party_number', 'String'),
    ('country_region', 'String'),
    ('_loaded_at', 'DateTime64(3)'),
    ('_raw_id', 'String'),
]) }}
{% else %}
{% for erp in erp_sources %}
select
    erp_source,
    entity_id,
    entity_name,
    accounting_currency,
    reporting_currency,
    party_number,
    country_region,
    _loaded_at,
    _raw_id
from {{ ref('stg_' ~ erp ~ '__legal_entities') }}
{% if not loop.last %}union all{% endif %}
{% endfor %}
{% endif %}
