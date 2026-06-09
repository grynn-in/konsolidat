-- PRD-11 Test: Every first acquisition with price > 0 must produce a goodwill entry
select
    op.consolidation_group,
    op.data_area_id,
    op.acquisition_price
from {{ source('epm_staging', 'ownership_periods') }} as op
left join {{ ref('gold_acquisition_adjustments') }} as ga
    on op.consolidation_group = ga.consolidation_group
    and op.data_area_id = ga.data_area_id
    and ga.adjustment_type = 'goodwill'
where op.is_first_acquisition = 1
  and op.acquisition_price > 0
  and ga.consolidation_group is null
