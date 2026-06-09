-- PRD-12 Test: Every disposal must produce a gain/loss entry
select
    op.consolidation_group,
    op.data_area_id,
    op.disposal_date
from {{ source('epm_staging', 'ownership_periods') }} as op
left join {{ ref('gold_disposal_adjustments') }} as da
    on op.consolidation_group = da.consolidation_group
    and op.data_area_id = da.data_area_id
    and da.adjustment_type = 'disposal_gain_loss'
where op.is_disposal = 1
  and op.disposal_date < toDate('9999-12-31')
  and da.consolidation_group is null
