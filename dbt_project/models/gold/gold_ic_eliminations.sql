{{
    config(
        query_settings={'allow_experimental_join_condition': 1},
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# Intercompany elimination entries. Each row is one two-legged entry:
   debit_account takes debit_elimination (negative) and credit_account takes
   credit_elimination (positive), so every row nets to zero.
   gold_fully_consolidated_tb books both legs as the ic_elimination layer.

   konsolidat#148: this used to sum each entity's WHOLE balance per account,
   then join every ordered debit-entity x credit-entity pair and eliminate the
   lesser balance for each, so N entities made N x (N-1) rows each consuming
   full balances: 2.61M eliminated against a 2.56M intercompany revenue
   balance, and 31.5M against 14.5M on a wrongly flagged AP account. It had no
   counterparty to pair on.

   Now (decided 13 Sep 2026, with konsol#159):
   - balance eliminations come from gold_ic_reconciliation, one row per pair
     of (entity, partner, account) and (partner, entity, counterpart), on
     accounts flagged in the group chart (Intercompany Account);
   - elimination_kind 'matched': the matched amount, the smaller side, when
     the two sides offset;
   - elimination_kind 'difference': what is left on each side after that is
     moved to the group's intercompany-difference account, so the pair's
     intercompany balances clear. A group without one books no difference:
     only the matched amount is eliminated and the rest stays visible on the
     intercompany accounts;
   - rows without a partner are never eliminated (gold_ic_unmatched);
   - IC Elimination Rules of type 'balance' no longer eliminate anything.
     The doctype stays for special cases: 'unrealized_profit' below.

   entity_a/account_a/entity_b/account_b name the pair a balance row belongs
   to ('' on unrealized-profit rows). #}

with ic_rules as (
    select
        rule_id,
        rule_name,
        debit_account,
        credit_account,
        debit_entity_pattern,
        credit_entity_pattern,
        rule_type,
        margin_pct,
        asset_account
    from {{ source('epm_staging', 'ic_elimination_rules') }}
),

pairs as (
    select
        *,
        {# what is left on each side once the matched amount is eliminated #}
        balance_a - sign(balance_a) * matched_amount as residual_a,
        balance_b - sign(balance_b) * matched_amount as residual_b
    from {{ ref('gold_ic_reconciliation') }}
),

matched_eliminations as (
    select
        concat('IC:', account_a, '/', account_b) as rule_id,
        'Intercompany: matched amount' as rule_name,
        'balance' as rule_type,
        consolidation_group,
        fiscal_year,
        fiscal_period,
        {# the side with the debit balance is credited, and vice versa #}
        if(balance_a > 0, account_a, account_b) as debit_account,
        if(balance_a > 0, account_b, account_a) as credit_account,
        if(balance_a > 0, entity_a, entity_b) as debit_entity,
        if(balance_a > 0, entity_b, entity_a) as credit_entity,
        matched_amount as elimination_amount,
        -matched_amount as debit_elimination,
        matched_amount as credit_elimination,
        'matched' as elimination_kind,
        entity_a,
        account_a,
        entity_b,
        account_b
    from pairs
    where matched_amount > 0
),

residuals as (
    select
        consolidation_group, fiscal_year, fiscal_period,
        entity_a, account_a, entity_b, account_b, ic_difference_account,
        entity_a as ic_entity, account_a as ic_account, entity_b as other_entity,
        residual_a as residual
    from pairs
    where ic_difference_account != '' and abs(residual_a) >= 0.005

    union all

    select
        consolidation_group, fiscal_year, fiscal_period,
        entity_a, account_a, entity_b, account_b, ic_difference_account,
        entity_b as ic_entity, account_b as ic_account, entity_a as other_entity,
        residual_b as residual
    from pairs
    where ic_difference_account != '' and abs(residual_b) >= 0.005
),

difference_eliminations as (
    select
        concat('IC:', account_a, '/', account_b) as rule_id,
        'Intercompany: difference' as rule_name,
        'balance' as rule_type,
        consolidation_group,
        fiscal_year,
        fiscal_period,
        {# clear the residual off the intercompany account; the difference
           account takes the same signed amount #}
        if(residual > 0, ic_account, ic_difference_account) as debit_account,
        if(residual > 0, ic_difference_account, ic_account) as credit_account,
        if(residual > 0, ic_entity, other_entity) as debit_entity,
        if(residual > 0, other_entity, ic_entity) as credit_entity,
        abs(residual) as elimination_amount,
        -abs(residual) as debit_elimination,
        abs(residual) as credit_elimination,
        'difference' as elimination_kind,
        entity_a,
        account_a,
        entity_b,
        account_b
    from residuals
),

{# PRD-15: Unrealized profit elimination
   elimination = ending_ic_inventory × margin%
   Dr Revenue offset, Cr Inventory #}
unrealized_profit_eliminations as (
    select
        icr.rule_id as rule_id,
        icr.rule_name as rule_name,
        icr.rule_type as rule_type,
        cg.consolidation_group as consolidation_group,
        icb.fiscal_year as fiscal_year,
        icb.fiscal_period as fiscal_period,
        icr.debit_account as debit_account,
        icr.asset_account as credit_account,
        icb.selling_entity as debit_entity,
        icb.buying_entity as credit_entity,
        icb.ending_inventory_from_ic * (icr.margin_pct / 100.0) as elimination_amount,
        -(icb.ending_inventory_from_ic * (icr.margin_pct / 100.0)) as debit_elimination,
        icb.ending_inventory_from_ic * (icr.margin_pct / 100.0) as credit_elimination,
        'unrealized_profit' as elimination_kind,
        '' as entity_a,
        '' as account_a,
        '' as entity_b,
        '' as account_b
    from ic_rules as icr
    cross join {{ source('epm_staging', 'ic_balances') }} as icb
    {# F2: which group an entity rolls into is now one row per ANCESTOR group, so
       an unrealized-profit elimination is raised in every group that holds the
       buyer — including a parent group, which the single-level seed join never
       reached. distinct because the ownership model is period-grained and this
       join only needs the membership. #}
    inner join (
        select distinct consolidation_group, data_area_id
        from {{ ref('gold_entity_ownership') }}
        where has_complete_chain = 1 and consolidation_method != 'equity'
    ) as cg
        on icb.buying_entity = cg.data_area_id
    where icr.rule_type = 'unrealized_profit'
      and icb.ending_inventory_from_ic > 0
      and icr.margin_pct > 0
      and (icr.debit_entity_pattern = '*' or icb.selling_entity = icr.debit_entity_pattern)
      and (icr.credit_entity_pattern = '*' or icb.buying_entity = icr.credit_entity_pattern)
)

select * from matched_eliminations
union all
select * from difference_eliminations
union all
select * from unrealized_profit_eliminations
