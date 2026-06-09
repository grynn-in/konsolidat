-- PRD-9 Test: Entities without temporal ownership must fall back to seed ownership
select
    ctb.consolidation_group,
    ctb.data_area_id,
    ctb.ownership_pct as used_pct,
    cg.ownership_pct / 100.0 as seed_pct
from {{ ref('gold_consolidated_trial_balance') }} as ctb
inner join {{ ref('consolidation_groups') }} as cg
    on ctb.data_area_id = cg.data_area_id
left join {{ source('epm_staging', 'ownership_periods') }} as op
    on ctb.consolidation_group = op.consolidation_group
    and ctb.data_area_id = op.data_area_id
where op.data_area_id is null
  and abs(ctb.ownership_pct - cg.ownership_pct / 100.0) > 0.001
limit 10
