{{
    config(
        engine='MergeTree()',
        order_by='(data_area_id, recid)'
    )
}}

select
    toInt64(RecId) as recid,
    toString(dataAreaId) as data_area_id,
    toString(BudgetModelId) as budget_model_id,
    toString(coalesce(BudgetTransactionCode, '')) as budget_transaction_code,
    toString(coalesce(ReasonComment, '')) as reason_comment,
    toString(BudgetStatus) as budget_status,
    toDate(coalesce(DocumentDate, '1900-01-01')) as document_date,
    toDateTime(_airbyte_extracted_at) as _airbyte_extracted_at,
    toString(_airbyte_raw_id) as _airbyte_raw_id
from {{ source('airbyte_raw', 'budget_register_entries') }}
