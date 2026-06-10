{#
    Canonical budget entries — UNION ALL from per-ERP adapters.
#}

{% set erp_sources = var('erp_sources', ['d365_fo']) %}

{% for erp in erp_sources %}
select * from {{ ref('stg_' ~ erp ~ '__budget_entries') }}
{% if not loop.last %}union all{% endif %}
{% endfor %}
