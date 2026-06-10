{#
    Canonical GL entries — UNION ALL from per-ERP adapters.
    Every ERP adapter must produce the same column set.
    Bronze models consume this instead of ERP-specific staging.
#}

{% set erp_sources = var('erp_sources', ['d365_fo']) %}

{% for erp in erp_sources %}
select * from {{ ref('stg_' ~ erp ~ '__gl_entries') }}
{% if not loop.last %}union all{% endif %}
{% endfor %}
