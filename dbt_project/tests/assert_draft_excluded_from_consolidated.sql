-- PRD-16 Test: Draft adjustments must never appear in the consolidated adjustments
select
    journal_id,
    status
from {{ source('epm_staging', 'consolidation_adjustments') }}
where status = 'Draft'
  and journal_id in (
    select journal_id from {{ ref('gold_consolidation_adjustments') }}
  )
