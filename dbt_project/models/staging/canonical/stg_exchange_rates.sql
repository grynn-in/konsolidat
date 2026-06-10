{#
    Canonical exchange rates — UNION ALL from per-ERP adapters.
#}

{% set erp_sources = var('erp_sources', ['d365_fo']) %}

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
