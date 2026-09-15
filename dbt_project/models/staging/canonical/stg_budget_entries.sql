{#
    Canonical budget entries — UNION ALL from per-ERP adapters, then dimension
    harmonization. Only canonical columns selected — adapter-specific fields
    (budget_register_entry_recid, include_in_cash_flow) joined from adapter.

    Dimensions harmonized centrally (keyed on per-row erp_source) over the
    budget dimension subset (cost_center, department — no business_unit).

    With no ERP listed in `erp_sources`, an empty relation with the same
    columns and types (empty_relation, macros/erp_sources.sql).
#}

{% set erp_sources = var('erp_sources', []) %}
{% set budget_dims = get_budget_dimensions() %}

{% if erp_sources | length == 0 %}
{% set columns = [
    ('erp_source', 'String'),
    ('record_id', 'UInt64'),
    ('entity_id', 'String'),
    ('posting_date', 'String'),
    ('main_account', 'String'),
    ('amount', 'Decimal(38, 9)'),
    ('transaction_amount', 'Decimal(38, 9)'),
    ('transaction_currency', 'String'),
    ('budget_model', 'String'),
    ('budget_status', 'String'),
] %}
{% for d in budget_dims %}{% do columns.append((d.name, 'String')) %}{% endfor %}
{% do columns.extend([('_loaded_at', 'DateTime64(3)'), ('_raw_id', 'String')]) %}
{{ empty_relation(columns) }}
{% else %}
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
{% endif %}
