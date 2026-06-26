{#
    Budget Register Entries staging model.
    Deduplicates by EntryNumber to produce header-level rows.
    D365-specific helper — not part of canonical interface.
#}

with numbered as (
    select
        *,
        row_number() over (partition by EntryNumber order by Date) as rn
    from {{ source('d365_raw', 'budget_register_entries') }}
),

deduplicated as (
    select * from numbered where rn = 1
)

select
    rowNumberInAllBlocks() as RecId,
    upper(coalesce(dataAreaId, LegalEntityId, '')) as dataAreaId,
    coalesce(BudgetModelId, '') as BudgetModelId,
    coalesce(BudgetCode, '') as BudgetTransactionCode,
    coalesce(ReasonComment, Comment, '') as ReasonComment,
    coalesce(Status, 'Completed') as BudgetStatus,
    toString(substring(coalesce(toString(Date), '1900-01-01'), 1, 10)) as DocumentDate,
    _airbyte_extracted_at,
    _airbyte_raw_id
from deduplicated
