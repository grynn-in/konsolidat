{{ config(severity='warn') }}
-- konsolidat#198 (design §5, row J10; PR #203 review 8): a submitted Business Disposal whose entity has no
-- trial-balance row (gold_trial_balance) in or before the disposal period. The disposal journal derecognises
-- the entity's balance sheet from the cumulative trial balance through the disposal period; with no rows there
-- is nothing to derecognise, so the journal posts only goodwill, FVA, NCI, CTA and the proceeds, and the gain or
-- loss equals proceeds - (goodwill + FVA) as if the entity had no net assets at all (the
-- goodwill_amortisation.disposal.sql fixture shows it: gain 2,022 on 9,000 with no trial balance). The
-- journal still balances, so nothing else names it; warn severity: the entity's trial balance up to the disposal
-- should be uploaded first (design §5: the disposal period-end balance sheet is what leaves the group), or the
-- group accepts the figure knowingly.
--
-- How it is found: the disposal date is mapped through epm_staging.fiscal_periods exactly as the journal does
-- (start_date <= d <= end_date, Closing skipped, the lowest period tuple), then the entity's gold_trial_balance
-- rows with a period tuple <= that period are counted. A disposal whose date has no calendar period is not
-- named here (assert_disposal_accounts_declared names it).
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
        bd.disposed_entity as disposed_entity,
        bd.disposal_date as disposal_date,
        dp.fiscal_year as fiscal_year,
        dp.fiscal_period as fiscal_period
    from {{ source('epm_staging', 'business_disposals') }} as bd
    inner join disposal_period as dp
        on dp.deal = bd.name
),

-- the entity's trial-balance rows in or before the disposal period (tuple order, never a date or month)
tb_rows as (
    select
        d.deal as deal,
        count() as n_rows
    from disposals as d
    inner join {{ ref('gold_trial_balance') }} as tb
        on tb.data_area_id = d.disposed_entity
    where (toUInt16(tb.fiscal_year), toUInt16(tb.fiscal_period)) <= (d.fiscal_year, d.fiscal_period)
    group by d.deal
)

select
    d.deal as business_disposal,
    d.consolidation_group as consolidation_group,
    d.disposed_entity as disposed_entity,
    d.disposal_date as disposal_date,
    d.fiscal_year as disposal_fiscal_year,
    d.fiscal_period as disposal_fiscal_period
from disposals as d
left join tb_rows as t
    on t.deal = d.deal
where coalesce(t.n_rows, 0) = 0
order by business_disposal
