-- PRD-13 Test: NCI movement. Two checks, one row each per entity-period that breaks them:
--   share_of_profit   equals the sum of nci_amount over the consolidated TB's P&L rows with the
--                     synthesized year-end close left out, exactly as gold_nci_attribution_journal
--                     excludes it (konsol#117 pair 2 review, finding 5): the close moves the year's
--                     result to retained earnings and is no profit of the period;
--   closing_balance   equals the minority's share of net assets at the closing rate: the sum of
--                     nci_amount over the entity's balance-sheet rows that are not equity, for every
--                     period up to and including this one (a self-join, not the model's window).
-- Fixture: dbt_project/test_fixtures/nci_attribution_journal.sql.
with close_keys as (
    select distinct data_area_id, fiscal_year, fiscal_period, main_account
    from {{ ref('gold_trial_balance_by_partner') }}
    where is_year_end_close = 1
),

profit_check as (
    select
        nm.consolidation_group as consolidation_group,
        nm.data_area_id as data_area_id,
        nm.fiscal_year as fiscal_year,
        nm.fiscal_period as fiscal_period,
        'share_of_profit' as kind,
        toFloat64(nm.share_of_profit) as model_value,
        toFloat64(tb_nci.nci_total) as expected_value
    from {{ ref('gold_nci_movement_schedule') }} as nm
    {# LEFT: an entity-period whose P&L is all close rows has no row below, and expects 0
       (unmatched columns fill 0 under join_use_nulls = 0). #}
    left join (
        select
            consolidation_group,
            data_area_id,
            fiscal_year,
            fiscal_period,
            sum(nci_amount) as nci_total
        from {{ ref('gold_consolidated_trial_balance') }}
        where is_pnl = 1
          and (data_area_id, fiscal_year, fiscal_period, main_account)
              not in (select data_area_id, fiscal_year, fiscal_period, main_account from close_keys)
        group by consolidation_group, data_area_id, fiscal_year, fiscal_period
    ) as tb_nci
        on nm.consolidation_group = tb_nci.consolidation_group
        and nm.data_area_id = tb_nci.data_area_id
        and nm.fiscal_year = tb_nci.fiscal_year
        and nm.fiscal_period = tb_nci.fiscal_period
),

closing_check as (
    select
        nm.consolidation_group as consolidation_group,
        nm.data_area_id as data_area_id,
        nm.fiscal_year as fiscal_year,
        nm.fiscal_period as fiscal_period,
        'closing_balance' as kind,
        toFloat64(any(nm.nci_closing_balance)) as model_value,
        sum(toFloat64(ctb.nci_amount)) as expected_value
    from {{ ref('gold_nci_movement_schedule') }} as nm
    inner join {{ ref('gold_consolidated_trial_balance') }} as ctb
        on ctb.consolidation_group = nm.consolidation_group
        and ctb.data_area_id = nm.data_area_id
    where (ctb.fiscal_year * 1000 + ctb.fiscal_period) <= (nm.fiscal_year * 1000 + nm.fiscal_period)
      and ctb.is_balance_sheet = 1
      and ctb.is_equity = 0
    group by nm.consolidation_group, nm.data_area_id, nm.fiscal_year, nm.fiscal_period
)

select * from profit_check where abs(model_value - expected_value) > 0.01
union all
select * from closing_check where abs(model_value - expected_value) > 0.01
