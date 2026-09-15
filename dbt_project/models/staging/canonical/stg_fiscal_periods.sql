{#
    Canonical fiscal periods — UNION ALL from per-ERP adapters.
    With no ERP listed in `erp_sources`, an empty relation with the same
    columns and types (empty_relation, macros/erp_sources.sql).
#}

{% set erp_sources = var('erp_sources', ['d365_fo']) %}

{% if erp_sources | length == 0 %}
{{ empty_relation([
    ('erp_source', 'String'),
    ('calendar_id', 'String'),
    ('calendar_name', 'String'),
    ('fiscal_year', 'String'),
    ('start_date', 'String'),
    ('end_date', 'String'),
    ('_loaded_at', 'DateTime64(3)'),
    ('_raw_id', 'String'),
]) }}
{% else %}
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
{% endif %}
