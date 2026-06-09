-- PRD-12 Test: Post-disposal periods must have zero ownership (entity excluded)
-- When temporal ownership records a disposal, no consolidated TB rows should exist
-- for that entity in periods after the disposal
select
    ctb.consolidation_group,
    ctb.data_area_id,
    ctb.fiscal_year,
    ctb.fiscal_period,
    ctb.ownership_pct
from {{ ref('gold_consolidated_trial_balance') }} as ctb
inner join {{ source('epm_staging', 'ownership_periods') }} as op
    on ctb.consolidation_group = op.consolidation_group
    and ctb.data_area_id = op.data_area_id
    and op.is_disposal = 1
where {{ build_date_from_year_period('ctb.fiscal_year', 'ctb.fiscal_period') }} > op.disposal_date
  and ctb.ownership_pct > 0
limit 10
