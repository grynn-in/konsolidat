{#
    Canonical GL entries — UNION ALL from per-ERP adapters, then dimension
    harmonization. Every ERP adapter must produce the same column set.
    Bronze models consume this instead of ERP-specific staging.

    Only canonical columns are selected — adapter-specific columns
    (e.g. reporting_currency_amount, general_journal_entry_recid)
    must be joined from the adapter directly if needed.

    Dimension values are harmonized centrally here (keyed on the per-row
    erp_source) via the dimension_mappings crosswalk; unmapped values pass
    through unchanged. See dim_harmonize_* in macros/dimension_helpers.sql.
#}

{% set erp_sources = var('erp_sources', ['d365_fo']) %}

with unioned as (
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
        dim_cost_center,
        dim_department,
        dim_business_unit,
        _loaded_at,
        _raw_id
    from {{ ref('stg_' ~ erp ~ '__gl_entries') }}
    {% if not loop.last %}union all{% endif %}
    {% endfor %}
)

select
    -- erp_source is qualified+aliased: it also exists in the mapping joins, so
    -- an unaliased qualified name would leak into the output column name.
    unioned.erp_source as erp_source,
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
    {{ dim_harmonize_select(raw_alias='unioned') }}
    unioned._loaded_at as _loaded_at,
    unioned._raw_id as _raw_id
from unioned
{{ dim_harmonize_joins('unioned.erp_source', raw_alias='unioned') }}
-- konsolidat#105: drop GL lines with no legal entity. Real D365 ships ~11% of GL
-- headers with an empty SubledgerVoucherDataAreaId; those rows cannot be attributed
-- to an entity or consolidated, and they fail test_canonical_gl_entries_not_null
-- (which blocks every downstream model in the governed `dbt build`).
where coalesce(unioned.entity_id, '') != ''
