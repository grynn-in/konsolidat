{{ config(severity='warn') }}
-- konsolidat#198 (design §3, row J7): a submitted Business Combination whose acquired net assets can only be
-- measured at a period-end LATER than the acquisition period. Measurement precedence for the net assets at
-- acquisition: (1) konsol's acquired-balances table, (2) the header's net_assets_acquired, (3) the entity's
-- trial balance at the first period-end on or after the acquisition date. The third is a proxy, and a
-- period-end later than the acquisition period carries post-acquisition results into the "acquired" equity
-- (group profit eliminated as if it were pre-acquisition), so it is named here at warn severity: the
-- accountant should record the acquisition balance sheet on the Business Combination in konsol (an
-- acquisition-date balance sheet is normal practice, design §2), or the group accepts the proxy knowingly.
--
-- How it is found: a deal with no acquired-balance rows and net_assets_acquired = 0 (so (1) and (2) are
-- out), whose entity's earliest gold_trial_balance period at or after the acquisition period is later than
-- that period. A deal with no trial balance at all is not named here (nothing measures it late;
-- assert_goodwill_calculated names it, since no goodwill can be posted). Today
-- gold_business_combination_journal posts only from the acquired-balances table (measurement_basis
-- 'acquired_balances') and nothing for the other two cases, so a deal named here has no journal yet; when the
-- trial-balance fallback lands, this is where its late measurement is reported.
-- Fixture: dbt_project/test_fixtures/assert_acquisition_measured_in_period.must_flag.sql.
with deal_period as (
    select
        bc.name as deal,
        argMin(toUInt16(fp.fiscal_year), (toUInt16(fp.fiscal_year), toUInt16(fp.fiscal_period))) as fiscal_year,
        argMin(toUInt16(fp.fiscal_period), (toUInt16(fp.fiscal_year), toUInt16(fp.fiscal_period))) as fiscal_period
    from {{ source('epm_staging', 'business_combinations') }} as bc
    cross join {{ source('epm_staging', 'fiscal_periods') }} as fp
    where fp.start_date <= bc.acquisition_date
      and fp.end_date >= bc.acquisition_date
      and fp.period_type != 'Closing'
    group by bc.name
),

-- deals konsol did not measure: no acquired balance sheet, no net-assets figure
unmeasured as (
    select
        bc.name as deal,
        bc.consolidation_group as consolidation_group,
        bc.acquired_entity as acquired_entity,
        bc.acquisition_date as acquisition_date,
        dp.fiscal_year as fiscal_year,
        dp.fiscal_period as fiscal_period
    from {{ source('epm_staging', 'business_combinations') }} as bc
    inner join deal_period as dp
        on dp.deal = bc.name
    left join (
        select parent, count() as n_rows
        from {{ source('epm_staging', 'business_combination_acquired_balances') }}
        group by parent
    ) as ab
        on ab.parent = bc.name
    where coalesce(ab.n_rows, 0) = 0
      and abs(toFloat64(bc.net_assets_acquired)) < 0.005
),

-- the first trial-balance period at or after the acquisition period (tuple order, never a date or month)
first_tb as (
    select
        u.deal as deal,
        min((toUInt16(tb.fiscal_year), toUInt16(tb.fiscal_period))) as first_period
    from unmeasured as u
    inner join {{ ref('gold_trial_balance') }} as tb
        on tb.data_area_id = u.acquired_entity
    where (toUInt16(tb.fiscal_year), toUInt16(tb.fiscal_period)) >= (u.fiscal_year, u.fiscal_period)
    group by u.deal
)

select
    u.deal as business_combination,
    u.consolidation_group as consolidation_group,
    u.acquired_entity as acquired_entity,
    u.acquisition_date as acquisition_date,
    u.fiscal_year as acquisition_fiscal_year,
    u.fiscal_period as acquisition_fiscal_period,
    tupleElement(f.first_period, 1) as measured_fiscal_year,
    tupleElement(f.first_period, 2) as measured_fiscal_period
from unmeasured as u
inner join first_tb as f
    on f.deal = u.deal
where f.first_period > (u.fiscal_year, u.fiscal_period)
