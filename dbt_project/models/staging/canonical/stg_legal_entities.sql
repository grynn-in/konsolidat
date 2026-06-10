{#
    Canonical legal entities — UNION ALL from per-ERP adapters.
#}

{% set erp_sources = var('erp_sources', ['d365_fo']) %}

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
