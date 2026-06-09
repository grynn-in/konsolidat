-- PRD-9 Test: When temporal ownership exists, the consolidated TB must use it
-- Check that ownership_pct matches the temporal staging record for the period
select
    ctb.consolidation_group,
    ctb.data_area_id,
    ctb.fiscal_year,
    ctb.fiscal_period,
    ctb.ownership_pct as used_pct,
    op.ownership_pct / 100.0 as expected_pct
from {{ ref('gold_consolidated_trial_balance') }} as ctb
inner join {{ source('epm_staging', 'ownership_periods') }} as op
    on ctb.consolidation_group = op.consolidation_group
    and ctb.data_area_id = op.data_area_id
    and {{ build_date_from_year_period('ctb.fiscal_year', 'ctb.fiscal_period') }}
        between op.effective_date and op.end_date
where abs(ctb.ownership_pct - op.ownership_pct / 100.0) > 0.001
limit 10
