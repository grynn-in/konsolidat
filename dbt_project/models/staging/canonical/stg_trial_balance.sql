{#
    Canonical trial balance — UNION ALL from per-ERP adapters.
    With no ERP listed in `erp_sources`, an empty relation with the same
    columns and types (empty_relation, macros/erp_sources.sql).
#}

{% set erp_sources = var('erp_sources', []) %}

{% if erp_sources | length == 0 %}
{{ empty_relation([
    ('erp_source', 'String'),
    ('entity_id', 'String'),
    ('main_account', 'String'),
    ('account_name', 'String'),
    ('fiscal_year', 'UInt16'),
    ('opening_balance', 'Decimal(38, 9)'),
    ('debit_amount', 'Decimal(38, 9)'),
    ('credit_amount', 'Decimal(38, 9)'),
    ('closing_balance', 'Decimal(38, 9)'),
    ('currency_code', 'String'),
    ('account_type', 'String'),
    ('partner_data_area_id', 'Nullable(String)'),
    ('_loaded_at', 'DateTime64(3)'),
    ('_raw_id', 'String'),
]) }}
{% else %}
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
    partner_data_area_id,
    _loaded_at,
    _raw_id
from {{ ref('stg_' ~ erp ~ '__trial_balance') }}
{% if not loop.last %}union all{% endif %}
{% endfor %}
{% endif %}
