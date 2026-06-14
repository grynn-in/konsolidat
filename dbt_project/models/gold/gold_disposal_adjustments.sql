{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-12: Disposal & deconsolidation
   - Disposal gain/loss = disposal_price - (net_assets × ownership%) - remaining_goodwill
   - P&L proration: include only pre-disposal months
   - CTA recycling: accumulated CTA reclassified to P&L at disposal date (IAS 21.48) #}

with disposal_periods as (
    select
        consolidation_group,
        data_area_id,
        ownership_pct,
        disposal_date,
        disposal_price
    from {{ source('epm_staging', 'ownership_periods') }}
    where is_disposal = 1
      and disposal_date < toDate('9999-12-31')
),

{# Net assets at disposal date #}
disposal_net_assets as (
    select
        dp.consolidation_group,
        dp.data_area_id,
        dp.disposal_date,
        dp.disposal_price,
        toFloat64(dp.ownership_pct) as ownership_pct,
        sum(case when ctb.is_balance_sheet = 1 then ctb.local_amount else 0 end) as net_assets
    from disposal_periods as dp
    inner join {{ ref('gold_consolidated_trial_balance') }} as ctb
        on dp.consolidation_group = ctb.consolidation_group
        and dp.data_area_id = ctb.data_area_id
    group by dp.consolidation_group, dp.data_area_id, dp.disposal_date,
             dp.disposal_price, dp.ownership_pct
),

{# Remaining goodwill from acquisition adjustments #}
remaining_goodwill as (
    select
        consolidation_group,
        data_area_id,
        sum(adjustment_amount) as goodwill_balance
    from {{ ref('gold_acquisition_adjustments') }}
    where adjustment_type = 'goodwill'
    group by consolidation_group, data_area_id
),

{# Disposal gain/loss #}
disposal_gain_loss as (
    select
        dna.consolidation_group,
        dna.data_area_id,
        toUInt16(toYear(dna.disposal_date)) as fiscal_year,
        toUInt8(toMonth(dna.disposal_date)) as fiscal_period,
        toFloat64(dna.disposal_price) as disposal_price,
        toFloat64(dna.net_assets) as net_assets,
        toFloat64(dna.ownership_pct) as ownership_pct,
        toFloat64(coalesce(rg.goodwill_balance, 0)) as remaining_goodwill,
        toFloat64(dna.disposal_price)
            - (toFloat64(dna.net_assets) * toFloat64(dna.ownership_pct) / 100.0)
            - toFloat64(coalesce(rg.goodwill_balance, 0)) as gain_loss_amount,
        'disposal_gain_loss' as adjustment_type,
        dna.disposal_date
    from disposal_net_assets as dna
    left join remaining_goodwill as rg
        on dna.consolidation_group = rg.consolidation_group
        and dna.data_area_id = rg.data_area_id
),

{# CTA recycling: accumulated CTA reclassified to P&L at disposal #}
cta_recycling as (
    select
        fx.consolidation_group,
        fx.data_area_id,
        toUInt16(toYear(dp.disposal_date)) as fiscal_year,
        toUInt8(toMonth(dp.disposal_date)) as fiscal_period,
        toFloat64(0) as disposal_price,
        toFloat64(0) as net_assets,
        toFloat64(dp.ownership_pct) as ownership_pct,
        toFloat64(0) as remaining_goodwill,
        -sum(fx.cta_amount) as gain_loss_amount,
        'cta_recycling' as adjustment_type,
        dp.disposal_date
    from {{ ref('gold_fx_revaluation') }} as fx
    inner join disposal_periods as dp
        on fx.consolidation_group = dp.consolidation_group
        and fx.data_area_id = dp.data_area_id
    group by fx.consolidation_group, fx.data_area_id,
             dp.disposal_date, dp.ownership_pct
)

select * from disposal_gain_loss
where abs(gain_loss_amount) > 0.01

union all

select * from cta_recycling
where abs(gain_loss_amount) > 0.01
