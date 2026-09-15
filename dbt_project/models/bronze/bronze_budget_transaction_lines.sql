{{
    config(
        engine='MergeTree()',
        order_by='(budget_register_entry_recid, recid)',
        partition_by='toYYYYMM(transaction_date)'
    )
}}

{#
    Consumes canonical stg_budget_entries for ERP-agnostic columns.
    Joins D365 F&O adapter for budget_register_entry_recid and
    include_in_cash_flow (D365-specific fields).

    With `d365_fo` not in `erp_sources`, an empty relation with the same
    columns and types (empty_relation, macros/erp_sources.sql).
#}

{% if 'd365_fo' in var('erp_sources', []) %}
select
    {{ cast_to_int64('b.record_id') }} as recid,
    {{ cast_to_int64('coalesce(d365.budget_register_entry_recid, 0)') }} as budget_register_entry_recid,
    {{ cast_to_date('b.posting_date') }} as transaction_date,
    {{ cast_to_string('b.main_account') }} as main_account,
    {{ cast_to_decimal128('b.amount', 2) }} as accounting_currency_amount,
    {{ cast_to_decimal128('b.transaction_amount', 2) }} as transaction_currency_amount,
    {{ cast_to_string("coalesce(b.transaction_currency, '')") }} as transaction_currency,
    {{ dim_select_from_source(prefix='b.', dims=get_budget_dimensions()) }},
    {{ cast_to_int8('coalesce(d365.include_in_cash_flow, 0)') }} as include_in_cash_flow,
    {{ cast_to_datetime('b._loaded_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('b._raw_id') }} as _airbyte_raw_id
from {{ ref('stg_budget_entries') }} b
left join {{ ref('stg_d365_fo__budget_entries') }} d365
    on b.record_id = d365.record_id
    and b.erp_source = 'd365_fo'
{% else %}
{% set columns = [
    ('recid', 'Int64'),
    ('budget_register_entry_recid', 'Int64'),
    ('transaction_date', 'Date'),
    ('main_account', 'String'),
    ('accounting_currency_amount', 'Decimal(38, 2)'),
    ('transaction_currency_amount', 'Decimal(38, 2)'),
    ('transaction_currency', 'String'),
] %}
{% for d in get_budget_dimensions() %}{% do columns.append((d.name, 'String')) %}{% endfor %}
{% do columns.extend([
    ('include_in_cash_flow', 'Int8'),
    ('_airbyte_extracted_at', 'DateTime'),
    ('_airbyte_raw_id', 'String'),
]) %}
{{ empty_relation(columns) }}
{% endif %}

{# Budget stays a full `table` (not incremental): it is low-volume and its
   staging record_id is rowNumberInAllBlocks() (positional, non-deterministic),
   which is unsafe as a ReplacingMergeTree/delete+insert dedup key. Make it
   incremental only once budget has a stable surrogate key. #}
