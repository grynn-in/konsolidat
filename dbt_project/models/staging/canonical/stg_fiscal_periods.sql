{#
    Canonical fiscal periods — UNION ALL from per-ERP adapters.
#}

{% set erp_sources = var('erp_sources', ['d365_fo']) %}

{% for erp in erp_sources %}
select
    erp_source,
    calendar_id,
    calendar_name,
    fiscal_year,
    start_date,
    end_date,
    _loaded_at,
    _raw_id
from {{ ref('stg_' ~ erp ~ '__fiscal_periods') }}
{% if not loop.last %}union all{% endif %}
{% endfor %}
