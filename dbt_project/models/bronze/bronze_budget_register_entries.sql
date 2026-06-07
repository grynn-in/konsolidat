{{
    config(
        engine='MergeTree()',
        order_by='(data_area_id, recid)'
    )
}}

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
from {{ ref('stg_d365__budget_register_entries') }}
