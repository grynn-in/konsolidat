{#
    Canonical exchange rates — UNION ALL from per-ERP adapters.
    With no ERP listed in `erp_sources`, an empty relation with the same
    columns and types (empty_relation, macros/erp_sources.sql).
#}

{% set erp_sources = var('erp_sources', []) %}

{% if erp_sources | length == 0 %}
{{ empty_relation([
    ('erp_source', 'String'),
    ('from_currency', 'String'),
    ('to_currency', 'String'),
    ('valid_from', 'Date'),
    ('valid_to', 'Date'),
    ('exchange_rate', 'Decimal(38, 9)'),
    ('rate_type', 'String'),
    ('_loaded_at', 'DateTime64(3)'),
    ('_raw_id', 'String'),
]) }}
{% else %}
{% for erp in erp_sources %}
select
    erp_source,
    from_currency,
    to_currency,
    valid_from,
    valid_to,
    exchange_rate,
    rate_type,
    _loaded_at,
    _raw_id
from {{ ref('stg_' ~ erp ~ '__exchange_rates') }}
{% if not loop.last %}union all{% endif %}
{% endfor %}
{% endif %}
