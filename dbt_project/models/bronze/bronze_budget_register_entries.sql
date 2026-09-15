{{
    config(
        engine='MergeTree()',
        order_by='(data_area_id, recid)'
    )
}}

{# D365 F&O only. With `d365_fo` not in `erp_sources`, an empty relation with
   the same columns and types (empty_relation, macros/erp_sources.sql). #}

{% if 'd365_fo' in var('erp_sources', []) %}
select
    {{ cast_to_int64('RecId') }} as recid,
    {{ cast_to_string('dataAreaId') }} as data_area_id,
    {{ cast_to_string('BudgetModelId') }} as budget_model_id,
    {{ cast_to_string("coalesce(BudgetTransactionCode, '')") }} as budget_transaction_code,
    {{ cast_to_string("coalesce(ReasonComment, '')") }} as reason_comment,
    {{ cast_to_string('BudgetStatus') }} as budget_status,
    {{ cast_to_date("coalesce(DocumentDate, '1900-01-01')") }} as document_date,
    {{ cast_to_datetime('_airbyte_extracted_at') }} as _airbyte_extracted_at,
    {{ cast_to_string('_airbyte_raw_id') }} as _airbyte_raw_id
from {{ ref('stg_d365_fo__budget_register_entries') }}
{% else %}
{{ empty_relation([
    ('recid', 'Int64'),
    ('data_area_id', 'String'),
    ('budget_model_id', 'String'),
    ('budget_transaction_code', 'String'),
    ('reason_comment', 'String'),
    ('budget_status', 'String'),
    ('document_date', 'Date'),
    ('_airbyte_extracted_at', 'DateTime'),
    ('_airbyte_raw_id', 'String'),
]) }}
{% endif %}
