{#
    Canonical chart of accounts — UNION ALL from per-ERP adapters.
#}

{% set erp_sources = var('erp_sources', ['d365_fo']) %}

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
