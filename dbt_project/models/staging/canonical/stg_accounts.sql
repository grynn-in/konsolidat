{#
    Canonical chart of accounts — UNION ALL from per-ERP adapters.
    With no ERP listed in `erp_sources`, an empty relation with the same
    columns and types (empty_relation, macros/erp_sources.sql).
#}

{% set erp_sources = var('erp_sources', ['d365_fo']) %}

{% if erp_sources | length == 0 %}
{{ empty_relation([
    ('erp_source', 'String'),
    ('account_id', 'String'),
    ('account_name', 'String'),
    ('account_type', 'String'),
    ('account_category', 'String'),
    ('debit_credit_default', 'String'),
    ('chart_of_accounts', 'String'),
    ('is_suspended', 'UInt8'),
    ('_loaded_at', 'DateTime64(3)'),
    ('_raw_id', 'String'),
]) }}
{% else %}
{% for erp in erp_sources %}
select
    erp_source,
    account_id,
    account_name,
    account_type,
    account_category,
    debit_credit_default,
    chart_of_accounts,
    is_suspended,
    _loaded_at,
    _raw_id
from {{ ref('stg_' ~ erp ~ '__accounts') }}
{% if not loop.last %}union all{% endif %}
{% endfor %}
{% endif %}
