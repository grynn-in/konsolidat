-- PRD-16 Test: Approved adjustments with auto_reverse_period > 0 must have
-- a corresponding auto-reversal row in gold_consolidation_adjustments
select
    sa.journal_id,
    sa.auto_reverse_period
from {{ source('epm_staging', 'consolidation_adjustments') }} as sa
left join {{ ref('gold_consolidation_adjustments') }} as ga
    on ga.reversal_journal_id = sa.journal_id
    and ga.adjustment_type = 'auto_reversal'
where sa.status = 'Approved'
  and sa.auto_reverse_period > 0
  and sa.reversal_journal_id = ''
  and ga.journal_id is null
