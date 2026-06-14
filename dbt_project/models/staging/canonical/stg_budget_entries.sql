{#
    Canonical budget entries — UNION ALL from per-ERP adapters, then dimension
    harmonization. Only canonical columns selected — adapter-specific fields
    (budget_register_entry_recid, include_in_cash_flow) joined from adapter.

    Dimensions harmonized centrally (keyed on per-row erp_source) over the
    budget dimension subset (cost_center, department — no business_unit).
#}

{% set erp_sources = var('erp_sources', ['d365_fo']) %}
{% set budget_dims = get_budget_dimensions() %}

with unioned as (
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
)

select
    unioned.erp_source as erp_source,
    record_id,
    entity_id,
    posting_date,
    main_account,
    amount,
    transaction_amount,
    transaction_currency,
    budget_model,
    budget_status,
    {{ dim_harmonize_select(raw_alias='unioned', dims=budget_dims) }}
    unioned._loaded_at as _loaded_at,
    unioned._raw_id as _raw_id
from unioned
{{ dim_harmonize_joins('unioned.erp_source', raw_alias='unioned', dims=budget_dims) }}
