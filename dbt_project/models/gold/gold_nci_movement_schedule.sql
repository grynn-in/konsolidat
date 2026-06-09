{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-13: NCI Movement Schedule
   Reconciliation: opening → share_of_profit → OCI → dividends → acquisition → disposal → closing
   Supports full vs partial goodwill methods #}

with nci_entities as (
    select
        cg.consolidation_group,
        cg.data_area_id,
        cg.entity_name,
        cg.ownership_pct / 100.0 as ownership_pct,
        1.0 - cg.ownership_pct / 100.0 as nci_pct,
        cg.reporting_currency,
        coalesce(cg.consolidation_method, 'full') as consolidation_method
    from {{ ref('consolidation_groups') }} as cg
    where cg.ownership_pct < 100
      and cg.consolidation_method = 'full'
),

{# NCI share of profit per period #}
nci_profit as (
    select
        ctb.consolidation_group,
        ctb.data_area_id,
        ctb.fiscal_year,
        ctb.fiscal_period,
        sum(ctb.nci_amount) as nci_share_of_profit
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    inner join nci_entities as ne
        on ctb.consolidation_group = ne.consolidation_group
        and ctb.data_area_id = ne.data_area_id
    where ctb.is_pnl = 1
    group by ctb.consolidation_group, ctb.data_area_id, ctb.fiscal_year, ctb.fiscal_period
),

{# NCI opening balance: cumulative BS NCI at period start #}
nci_bs_balance as (
    select
        ctb.consolidation_group,
        ctb.data_area_id,
        ctb.fiscal_year,
        ctb.fiscal_period,
        sum(ctb.nci_amount) as nci_bs_total
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    inner join nci_entities as ne
        on ctb.consolidation_group = ne.consolidation_group
        and ctb.data_area_id = ne.data_area_id
    where ctb.is_balance_sheet = 1
    group by ctb.consolidation_group, ctb.data_area_id, ctb.fiscal_year, ctb.fiscal_period
),

{# Build movement schedule per entity per period #}
movement_schedule as (
    select
        ne.consolidation_group,
        ne.data_area_id,
        ne.entity_name,
        coalesce(np.fiscal_year, nb.fiscal_year) as fiscal_year,
        coalesce(np.fiscal_period, nb.fiscal_period) as fiscal_period,
        ne.nci_pct,
        coalesce(nb.nci_bs_total, 0) as nci_closing_balance,
        coalesce(np.nci_share_of_profit, 0) as share_of_profit,
        ne.consolidation_method
    from nci_entities as ne
    left join nci_profit as np
        on ne.consolidation_group = np.consolidation_group
        and ne.data_area_id = np.data_area_id
    left join nci_bs_balance as nb
        on ne.consolidation_group = nb.consolidation_group
        and ne.data_area_id = nb.data_area_id
        and np.fiscal_year = nb.fiscal_year
        and np.fiscal_period = nb.fiscal_period
)

select
    consolidation_group,
    data_area_id,
    entity_name,
    fiscal_year,
    fiscal_period,
    nci_pct,
    nci_closing_balance,
    share_of_profit,
    consolidation_method
from movement_schedule
where fiscal_year is not null
