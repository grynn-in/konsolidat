{#
    Consolidation Account Groups staging model.
    Deduplicates by ConsolidationAccountGroup.
#}

with numbered as (
    select
        *,
        row_number() over (partition by ConsolidationAccountGroup order by ConsolidationAccountGroup) as rn
    from {{ source('d365_raw', 'consolidate_account_groups') }}
),

deduplicated as (
    select * from numbered where rn = 1
)

select
    coalesce(ConsolidationAccountGroup, '') as ConsolidationAccountGroup,
    coalesce(ConsolidationAccountGroupName, '') as Name,
    '' as Description,
    rowNumberInAllBlocks() as RecId,
    _airbyte_extracted_at,
    _airbyte_raw_id
from deduplicated
