{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-13: NCI Movement Schedule
   Reconciliation: opening → share_of_profit → OCI → dividends → acquisition → disposal → closing
   Supports full vs partial goodwill methods

   konsol#117 pair 2 K2: share_of_profit is the P&L leg of the NCI attribution
   journal (gold_nci_attribution_journal), which posts the minority's share of
   the result and CTA to the group's nci_account. This schedule's closing
   balance is the minority's share of net assets at closing; under full-goodwill
   measurement it differs from the fully consolidated TB's nci_account balance
   by the acquisition-date premium (follow-up F1).

   Review fix (konsol#117 pair 2, finding 5), so the schedule agrees with that header:
     share_of_profit    the sum of nci_amount over the entity-period's P&L rows,
                        the synthesized year-end close left out (is_year_end_close, by
                        entity / FY / period / account) exactly as the attribution
                        journal leaves it out: the close moves the year's result to
                        retained earnings and is no profit of its period, so P13
                        shows 0 where it used to show -(the year);
     nci_closing_balance the minority's share of net assets at the closing rate:
                        the CUMULATIVE sum of nci_amount over the entity's
                        balance-sheet rows that are not equity, every period up to
                        and including this one. It used to be the period's
                        MOVEMENT over all balance-sheet rows, equity included. #}

{# F2: ownership comes from gold_entity_ownership — dated, chain-multiplied and
   resolved once. This read the consolidation_groups seed, so an entity's NCI was
   computed from a June CSV and only ever against its immediate parent group; a
   sub-group's minority interest never reached the top group at all. #}
with nci_entities as (
    select
        eo.consolidation_group as consolidation_group,
        eo.data_area_id as data_area_id,
        eo.fiscal_year as fiscal_year,
        eo.fiscal_period as fiscal_period,
        cg.entity_name as entity_name,
        eo.effective_ownership_pct as ownership_pct,
        1.0 - eo.effective_ownership_pct as nci_pct,
        grp.reporting_currency as reporting_currency,
        eo.consolidation_method as consolidation_method
    from {{ ref('gold_entity_ownership') }} as eo
    {# On data_area_id ALONE: the node carrying an entity's name is the one that
       owns it, and an entity is a node exactly once
       (ConsolidationGroup._validate_entity_in_one_node,
       assert_entity_in_one_consolidation_node). Keying on the consolidating
       group as well matched only the immediate parent, so every entity reached
       through a sub-group — the rows this work exists to produce — came out
       with a blank name in the top group's schedule. #}
    left join {{ source('epm_gold', 'consolidation_groups') }} as cg
        on cg.data_area_id = eo.data_area_id
    left join {{ source('epm_gold', 'consolidation_groups') }} as grp
        on grp.consolidation_group = eo.consolidation_group
        and grp.data_area_id = ''
    where eo.has_complete_chain = 1
      and eo.effective_ownership_pct < 1.0
      and eo.consolidation_method = 'full'
),

{# The synthesized year-end close: rows of these keys are no profit of the period. #}
close_keys as (
    select distinct data_area_id, fiscal_year, fiscal_period, main_account
    from {{ ref('gold_trial_balance_by_partner') }}
    where is_year_end_close = 1
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
        and ctb.fiscal_year = ne.fiscal_year
        and ctb.fiscal_period = ne.fiscal_period
    where ctb.is_pnl = 1
      and (ctb.data_area_id, ctb.fiscal_year, ctb.fiscal_period, ctb.main_account)
          not in (select data_area_id, fiscal_year, fiscal_period, main_account from close_keys)
    group by ctb.consolidation_group, ctb.data_area_id, ctb.fiscal_year, ctb.fiscal_period
),

{# The minority's share of net assets at the closing rate, per period: the NCI
   amount of the non-equity balance-sheet rows is the period's movement of the
   entity's net assets (translated at the closing rate, retranslation included).
   Summed over EVERY period of the entity in the group (not only the periods the
   entity is partly owned in: the figure is a running balance), then accumulated
   below. #}
nci_bs_movement as (
    select
        ctb.consolidation_group as consolidation_group,
        ctb.data_area_id as data_area_id,
        ctb.fiscal_year as fiscal_year,
        ctb.fiscal_period as fiscal_period,
        sum(ctb.nci_amount) as nci_bs_total
    from {{ ref('gold_consolidated_trial_balance') }} as ctb
    where ctb.is_balance_sheet = 1
      and ctb.is_equity = 0
      and (ctb.consolidation_group, ctb.data_area_id) in
          (select consolidation_group, data_area_id from nci_entities)
    group by ctb.consolidation_group, ctb.data_area_id, ctb.fiscal_year, ctb.fiscal_period
),

nci_bs_balance as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        sum(nci_bs_total) over (
            partition by consolidation_group, data_area_id
            order by fiscal_year, fiscal_period
            rows between unbounded preceding and current row
        ) as nci_bs_total
    from nci_bs_movement
),

{# Build movement schedule per entity per period #}
nci_periods as (
    select consolidation_group, data_area_id, fiscal_year, fiscal_period from nci_profit
    union distinct
    select consolidation_group, data_area_id, fiscal_year, fiscal_period from nci_bs_balance
),

movement_schedule as (
    select
        ne.consolidation_group as consolidation_group,
        ne.data_area_id as data_area_id,
        ne.entity_name as entity_name,
        pr.fiscal_year as fiscal_year,
        pr.fiscal_period as fiscal_period,
        ne.nci_pct as nci_pct,
        coalesce(nb.nci_bs_total, 0) as nci_closing_balance,
        coalesce(np.nci_share_of_profit, 0) as share_of_profit,
        ne.consolidation_method as consolidation_method
    from nci_entities as ne
    {# nci_entities is period-grained since F2 (ownership is dated), so this
       join carries the period too — without it every entity-period row would
       pair with every period and fan the schedule out. #}
    inner join nci_periods as pr
        on pr.consolidation_group = ne.consolidation_group and pr.data_area_id = ne.data_area_id
        and pr.fiscal_year = ne.fiscal_year and pr.fiscal_period = ne.fiscal_period
    left join nci_profit as np
        on np.consolidation_group = ne.consolidation_group and np.data_area_id = ne.data_area_id
        and np.fiscal_year = pr.fiscal_year and np.fiscal_period = pr.fiscal_period
    left join nci_bs_balance as nb
        on nb.consolidation_group = ne.consolidation_group and nb.data_area_id = ne.data_area_id
        and nb.fiscal_year = pr.fiscal_year and nb.fiscal_period = pr.fiscal_period
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
