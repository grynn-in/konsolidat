-- konsolidat#316 (decided 14 Nov 2026 by Deepak Pai, option A: one journal_close layer in
-- gold_fully_consolidated_tb). Year-end closed: for each consolidation group and fiscal year
-- with a declared Closing period, the P&L of every journal layer (adjustment_type != 'entity')
-- must sum to zero over the year's periods up to AND including the Closing period, once the
-- journal_close layer has moved it into retained earnings.
--
-- P&L = silver_main_accounts.is_pnl = 1, or an account in journal_pnl_pseudo_accounts()
-- (EQ_INCOME, outside the chart). Entity rows are the #259 close's job. ic_elimination is
-- EXCLUDED from the close (journal_close_excluded_layers()) but CHECKED here: it reverses its
-- own P&L legs with the entity close in the Closing period and so must net to zero by itself.
-- The design note is on #316 (chosen under the 5 Nov 2026 standing rule).
--
-- Closed layers net with the close PER ACCOUNT: for every layer not in
-- journal_close_excluded_layers(), together with 'journal_close', the year's P&L to the Closing
-- period sums to zero per (group, year, account), so one layer's error cannot hide behind
-- another's. Each excluded layer other than entity (ic_elimination) must net to zero by itself,
-- per adjustment_type, as before.
--
-- Rows returned (ERROR severity), with main_account ('' when not per account) and the
-- contributing adjustment_types:
--   open               |sum| > materiality_floor() for (group, year, account) over the closed
--                      layers and journal_close, or for (group, year, adjustment_type) of an
--                      excluded layer other than entity
--   no_closing_period  journal-layer P&L exists in a year with no declared Closing period while a
--                      later fiscal year is present in the table: nothing can close it
-- The Closing period is the first period_type = 'Closing' of the year in
-- epm_staging.fiscal_periods, as silver_tb_movements finds it. Postings after it are not summed.
-- Fixtures: test_fixtures/assert_journal_pnl_closed_at_year_end.*.sql
with closing_periods as (
    select fiscal_year, min(fiscal_period) as closing_period
    from {{ source('epm_staging', 'fiscal_periods') }}
    where period_type = 'Closing'
    group by fiscal_year
),

journal_pnl as (
    select
        f.consolidation_group as consolidation_group,
        f.fiscal_year as fiscal_year,
        f.fiscal_period as fiscal_period,
        f.adjustment_type as adjustment_type,
        f.main_account as main_account,
        f.amount as amount
    from {{ ref('gold_fully_consolidated_tb') }} as f
    left join {{ ref('silver_main_accounts') }} as ma
        on ma.main_account_id = f.main_account
    where f.adjustment_type != 'entity'
      and (ma.is_pnl = 1
           or f.main_account in ({{ "'" ~ journal_pnl_pseudo_accounts() | join("','") ~ "'" }}))
),

last_year as (
    select max(fiscal_year) as max_year
    from {{ ref('gold_fully_consolidated_tb') }}
),

open_closed_layers as (
    select
        p.consolidation_group as consolidation_group,
        p.fiscal_year as fiscal_year,
        p.main_account as main_account,
        arraySort(groupUniqArray(p.adjustment_type)) as adjustment_types,
        sum(p.amount) as open_amount,
        'open' as reason
    from journal_pnl as p
    inner join closing_periods as c on c.fiscal_year = p.fiscal_year
    where p.fiscal_period <= c.closing_period
      and p.adjustment_type not in ({{ "'" ~ journal_close_excluded_layers() | join("','") ~ "'" }})
    group by p.consolidation_group, p.fiscal_year, p.main_account
    having abs(sum(p.amount)) > {{ materiality_floor() }}
),

open_excluded_layers as (
    select
        p.consolidation_group as consolidation_group,
        p.fiscal_year as fiscal_year,
        '' as main_account,
        [p.adjustment_type] as adjustment_types,
        sum(p.amount) as open_amount,
        'open' as reason
    from journal_pnl as p
    inner join closing_periods as c on c.fiscal_year = p.fiscal_year
    where p.fiscal_period <= c.closing_period
      and p.adjustment_type in ({{ "'" ~ journal_close_excluded_layers() | join("','") ~ "'" }})
    group by p.consolidation_group, p.fiscal_year, p.adjustment_type
    having abs(sum(p.amount)) > {{ materiality_floor() }}
),

no_closing as (
    select
        p.consolidation_group as consolidation_group,
        p.fiscal_year as fiscal_year,
        '' as main_account,
        arraySort(groupUniqArray(p.adjustment_type)) as adjustment_types,
        sum(p.amount) as open_amount,
        'no_closing_period' as reason
    from journal_pnl as p
    where p.fiscal_year not in (select fiscal_year from closing_periods)
      and p.fiscal_year < (select max_year from last_year)
    group by p.consolidation_group, p.fiscal_year
)

select * from open_closed_layers
union all
select * from open_excluded_layers
union all
select * from no_closing
