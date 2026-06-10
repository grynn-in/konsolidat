{#
    Canonical fiscal periods — UNION ALL from per-ERP adapters.
#}

{% set erp_sources = var('erp_sources', ['d365_fo']) %}

{% for erp in erp_sources %}
select * from {{ ref('stg_' ~ erp ~ '__fiscal_periods') }}
{% if not loop.last %}union all{% endif %}
{% endfor %}
