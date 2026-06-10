{#
    Canonical budget entries — UNION ALL from per-ERP adapters.
    Only canonical columns selected — adapter-specific fields
    (budget_register_entry_recid, include_in_cash_flow) joined from adapter.
#}

{% set erp_sources = var('erp_sources', ['d365_fo']) %}

{% for erp in erp_sources %}
select
    erp_source,
    record_id,
    entity_id,
    posting_date,
    main_account,
    amount,
    transaction_amount,
    transaction_currency,
    budget_model,
    budget_status,
    dim_cost_center,
    dim_department,
    _loaded_at,
    _raw_id
from {{ ref('stg_' ~ erp ~ '__budget_entries') }}
{% if not loop.last %}union all{% endif %}
{% endfor %}
