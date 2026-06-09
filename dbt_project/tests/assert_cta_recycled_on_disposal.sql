-- PRD-12 Test: CTA must be recycled to P&L on disposal (IAS 21.48)
select
    dp.consolidation_group,
    dp.data_area_id,
    dp.disposal_date
from (
    select distinct consolidation_group, data_area_id, disposal_date
    from {{ source('epm_staging', 'ownership_periods') }}
    where is_disposal = 1
) as dp
inner join {{ ref('gold_fx_revaluation') }} as fx
    on dp.consolidation_group = fx.consolidation_group
    and dp.data_area_id = fx.data_area_id
left join {{ ref('gold_disposal_adjustments') }} as da
    on dp.consolidation_group = da.consolidation_group
    and dp.data_area_id = da.data_area_id
    and da.adjustment_type = 'cta_recycling'
where da.consolidation_group is null
