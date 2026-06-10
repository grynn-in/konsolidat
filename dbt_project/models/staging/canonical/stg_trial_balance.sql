{#
    Canonical trial balance — UNION ALL from per-ERP adapters.
#}

{% set erp_sources = var('erp_sources', ['d365_fo']) %}

{% for erp in erp_sources %}
select
    erp_source,
    entity_id,
    main_account,
    account_name,
    fiscal_year,
    opening_balance,
    debit_amount,
    credit_amount,
    closing_balance,
    currency_code,
    account_type,
    _loaded_at,
    _raw_id
from {{ ref('stg_' ~ erp ~ '__trial_balance') }}
{% if not loop.last %}union all{% endif %}
{% endfor %}
