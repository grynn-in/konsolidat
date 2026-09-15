-- PRD-12 test: CTA must be recycled to P&L on disposal (IAS 21.48).
--
-- konsolidat#198 (row J6b): rewritten to read epm_staging.business_disposals instead of
-- ownership_periods, and gold_business_disposal_journal instead of gold_disposal_adjustments.
-- Why: since konsolidat#198 the disposal lives on the submitted Business Disposal document (submit =
-- approval), and gold_business_disposal_journal recycles the disposed entity's accumulated CTA as its
-- `cta` line (account_role 'cta', main_account 'CTA'); gold_disposal_adjustments, which posted the
-- one-sided 'cta_recycling' row this test used to look for, is gone. The Ownership Period only carries
-- the effective share and the consolidation window, so an is_disposal Ownership Period is no longer a
-- deal the warehouse must account for (on the stack the deals are still Drafts: nothing submitted).
--
-- Flags a submitted disposal of an entity whose accumulated CTA in the group, from gold_fx_revaluation
-- up to and including the disposal period, is not zero, when the disposal journal has no `cta` line.
-- The disposal period is the calendar period (epm_staging.fiscal_periods, start_date <= date <=
-- end_date, Closing periods skipped) holding the disposal date, exactly as the journal maps it, and
-- the CTA is summed by (fiscal_year, fiscal_period) tuple, never by date or month. A disposal with a
-- retained interest posts no journal at all, so a non-zero CTA names it here as well as in
-- assert_disposal_gain_loss_exists. A disposal date outside the declared calendar has no period and
-- is not checked here (row J7's guard names it). A same-currency entity's CTA is 0 and is never owed.
with disposal_period as (
    select
        bd.name as deal,
        argMin(toUInt16(fp.fiscal_year), (toUInt16(fp.fiscal_year), toUInt16(fp.fiscal_period))) as fiscal_year,
        argMin(toUInt16(fp.fiscal_period), (toUInt16(fp.fiscal_year), toUInt16(fp.fiscal_period))) as fiscal_period
    from {{ source('epm_staging', 'business_disposals') }} as bd
    cross join {{ source('epm_staging', 'fiscal_periods') }} as fp
    where fp.start_date <= bd.disposal_date
      and fp.end_date >= bd.disposal_date
      and fp.period_type != 'Closing'
    group by bd.name
),

disposals as (
    select
        bd.name as deal,
        bd.consolidation_group as consolidation_group,
        bd.disposed_entity as data_area_id,
        bd.disposal_date as disposal_date,
        dp.fiscal_year as fiscal_year,
        dp.fiscal_period as fiscal_period
    from {{ source('epm_staging', 'business_disposals') }} as bd
    inner join disposal_period as dp
        on dp.deal = bd.name
),

accumulated_cta as (
    select
        d.deal as deal,
        sum(fx.cta_amount) as accumulated_cta
    from {{ ref('gold_fx_revaluation') }} as fx
    inner join disposals as d
        on d.consolidation_group = fx.consolidation_group
        and d.data_area_id = fx.data_area_id
    where (toUInt16(fx.fiscal_year), toUInt16(fx.fiscal_period)) <= (d.fiscal_year, d.fiscal_period)
    group by d.deal
),

cta_lines as (
    select deal, count() as n_lines
    from {{ ref('gold_business_disposal_journal') }}
    where account_role = 'cta'
    group by deal
)

select
    d.deal as business_disposal,
    d.consolidation_group,
    d.data_area_id as disposed_entity,
    d.disposal_date,
    c.accumulated_cta
from disposals as d
inner join accumulated_cta as c
    on c.deal = d.deal
left join cta_lines as l
    on l.deal = d.deal
where abs(c.accumulated_cta) > 0.01
  and coalesce(l.n_lines, 0) = 0
