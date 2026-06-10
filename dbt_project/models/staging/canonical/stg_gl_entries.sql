{#
    Canonical GL entries — UNION ALL from per-ERP adapters.
    Every ERP adapter must produce the same column set.
    Bronze models consume this instead of ERP-specific staging.

    Only canonical columns are selected — adapter-specific columns
    (e.g. reporting_currency_amount, general_journal_entry_recid)
    must be joined from the adapter directly if needed.
#}

{% set erp_sources = var('erp_sources', ['d365_fo']) %}

{% for erp in erp_sources %}
select
    erp_source,
    record_id,
    entity_id,
    posting_date,
    fiscal_year,
    fiscal_period,
    main_account,
    account_name,
    amount,
    transaction_currency_amount,
    transaction_currency,
    description,
    journal_number,
    posting_type,
    ledger_account,
    is_credit,
    dim_cost_center,
    dim_department,
    dim_business_unit,
    _loaded_at,
    _raw_id
from {{ ref('stg_' ~ erp ~ '__gl_entries') }}
{% if not loop.last %}union all{% endif %}
{% endfor %}
