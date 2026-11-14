-- konsolidat#316 (decided 14 Nov 2026 by Deepak Pai, option A: one journal_close layer in
-- gold_fully_consolidated_tb). Year-end closed: for each consolidation group and fiscal year
-- with a declared Closing period that a later fiscal year follows, the P&L of every journal layer (adjustment_type != 'entity')
-- must sum to zero over the year's periods up to AND including the Closing period, once the
-- journal_close layer has moved it into retained earnings.
--
-- P&L = silver_main_accounts.is_pnl = 1, or an account in journal_pnl_pseudo_accounts()
-- (EQ_INCOME, outside the chart). Entity rows are the #259 close's job. ic_elimination is
-- EXCLUDED from the close (journal_close_excluded_layers()) but CHECKED here: it reverses its
-- own P&L legs with the entity close in the Closing period and so must net to zero by itself.
-- The design note is on #316 (chosen under the 5 Nov 2026 standing rule).
--
-- Closed years only (#357 review F1/F2): a (group, fiscal year) is judged only when a LATER fiscal
-- year follows it in the group's rows of gold_fully_consolidated_tb (journal_close excluded), the
-- rule the journal close (journal_close_years) and the #259 entity close (silver_tb_movements
-- years_to_close: fiscal_year < last_year) both follow. The group's last, open year is not closed
-- yet: its journal P&L and its ic_elimination P&L stay open, as its entity P&L does.
--
-- Closed layers net with the close PER ACCOUNT: for every layer not in
-- journal_close_excluded_layers(), together with 'journal_close', the year's P&L to the Closing
-- period sums to zero per (group, year, account), so one layer's error cannot hide behind
-- another's. Each excluded layer other than entity (ic_elimination) must net to zero by itself,
-- per adjustment_type: the #259 close reverses its P&L legs in the Closing period.
--
-- Rows returned (ERROR severity), with main_account ('' when not per account) and the
-- contributing adjustment_types:
--   open               in a closed year, |sum| > materiality_floor() for (group, year, account)
--                      over the closed layers and journal_close, or for (group, year,
--                      adjustment_type) of an excluded layer other than entity
--   after_closing      in a closed year, journal-layer P&L posted in a period AFTER the Closing
--                      period (e.g. an Adjustment period P14) with |sum| > materiality_floor() per
--                      (group, year, account): the close sums to the Closing period, so it stays open
--   no_closing_period  journal-layer P&L in a year with no declared Closing period while a later
--                      fiscal year follows it for the group: nothing can close it
-- The Closing period is the first period_type = 'Closing' of the year in
-- epm_staging.fiscal_periods, as silver_tb_movements finds it.
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

group_years as (
    select consolidation_group, max(fiscal_year) as last_year
    from {{ ref('gold_fully_consolidated_tb') }}
    where adjustment_type != 'journal_close'
    group by consolidation_group
),

{# journal P&L of closed years: a later fiscal year follows, and a Closing period is declared #}
closed_pnl as (
    select
        p.consolidation_group as consolidation_group,
        p.fiscal_year as fiscal_year,
        p.fiscal_period as fiscal_period,
        p.adjustment_type as adjustment_type,
        p.main_account as main_account,
        p.amount as amount,
        c.closing_period as closing_period
    from journal_pnl as p
    inner join group_years as g on g.consolidation_group = p.consolidation_group
    inner join closing_periods as c on c.fiscal_year = p.fiscal_year
    where p.fiscal_year < g.last_year
),

open_closed_layers as (
    select
        p.consolidation_group as consolidation_group,
        p.fiscal_year as fiscal_year,
        p.main_account as main_account,
        arraySort(groupUniqArray(p.adjustment_type)) as adjustment_types,
        sum(p.amount) as open_amount,
        'open' as reason
    from closed_pnl as p
    where p.fiscal_period <= p.closing_period
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
    from closed_pnl as p
    where p.fiscal_period <= p.closing_period
      and p.adjustment_type in ({{ "'" ~ journal_close_excluded_layers() | join("','") ~ "'" }})
    group by p.consolidation_group, p.fiscal_year, p.adjustment_type
    having abs(sum(p.amount)) > {{ materiality_floor() }}
),

after_closing as (
    select
        p.consolidation_group as consolidation_group,
        p.fiscal_year as fiscal_year,
        p.main_account as main_account,
        arraySort(groupUniqArray(p.adjustment_type)) as adjustment_types,
        sum(p.amount) as open_amount,
        'after_closing' as reason
    from closed_pnl as p
    where p.fiscal_period > p.closing_period
    group by p.consolidation_group, p.fiscal_year, p.main_account
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
    inner join group_years as g on g.consolidation_group = p.consolidation_group
    where p.fiscal_year not in (select fiscal_year from closing_periods)
      and p.fiscal_year < g.last_year
    group by p.consolidation_group, p.fiscal_year
)

select * from open_closed_layers
union all
select * from open_excluded_layers
union all
select * from after_closing
union all
select * from no_closing
