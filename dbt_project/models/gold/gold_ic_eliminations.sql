{{
    config(
        query_settings={'allow_experimental_join_condition': 1},
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# Intercompany elimination entries. Each row is one two-legged entry in the
   group view: debit_account takes debit_elimination (<= 0) and credit_account
   takes credit_elimination (>= 0), so every row nets to zero.
   gold_fully_consolidated_tb books both legs as the ic_elimination layer.

   konsolidat#148: this used to sum each entity's WHOLE balance per account,
   then join every ordered debit-entity x credit-entity pair and eliminate the
   lesser balance for each: 2.61M eliminated against a 2.56M intercompany
   revenue balance. It had no counterparty to pair on.

   Balance eliminations come from gold_ic_reconciliation, one row per pair and
   period (decided 13 Sep 2026):
   - 'matched': the matched amount (the smaller side, at 100%), eliminated from
     both sides at the share of it both hold in the group view,
     least(share_a, share_b).
   - 'nci' (decision 12): the side the group holds more of (for example the
     100%-owned entity against an 80%-owned one) is eliminated at its own
     share. The rest of it goes to the NCI line (ic_nci_account(), attributed
     to the entity whose minority owners hold it), not to the difference
     account. With 1000 against 1000 at 100% and 80%, the group view
     eliminates 1000 and 800 and puts 200 to NCI.
     The NCI figures themselves (gold_nci_movement_schedule, nci_amount) are
     untouched. Eliminating an intragroup balance does not change the
     minority owners' share of the subsidiary. Their 200 of the payable stays
     in the NCI figures, and the NCI line in the group view is its
     counterpart, so the group view and the NCI figures each still balance.
   - 'difference': what is left of each side after that (the 100% residual)
     at the side's share, moved to the group's intercompany-difference account
     and labelled with the pair's difference_cause (decision 13). A group
     without one books no difference: the rest stays on the IC accounts.
   - Decision 14: a balance-sheet pair is valued at its balance to date, so
     the amounts above are eliminations TO DATE. The group view holds
     movements, so each period posts the change since the pair's previous
     row. A timing difference booked to the difference account in one period
     is reversed out of it in the period the partner catches up. A P&L pair is
     valued at the period's movement and posts it as it is.
   - Rows without a partner are never eliminated (gold_ic_unmatched).
     Balance-type IC Elimination Rules no longer eliminate anything. The
     doctype stays for special cases: 'unrealized_profit' below. #}

{% set pair = "consolidation_group, entity_a, account_a, entity_b, account_b" %}
{% set to_date = "partition by " ~ pair ~ " order by fiscal_year, fiscal_period rows between unbounded preceding and current row" %}

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
        consolidation_group, fiscal_year, fiscal_period, basis,
        entity_a, account_a, entity_b, account_b,
        ic_difference_account, difference_cause,
        share_a, share_b,
        {# each side's full (100%) elimination: it takes the side to its residual #}
        -sign(balance_a) * matched_amount as full_a,
        -sign(balance_b) * matched_amount as full_b,
        residual_a,
        residual_b
    from {{ ref('gold_ic_reconciliation') }}
),

{# every leg on the pair's basis: to date (balance) or for the period (movement) #}
at_basis as (
    select
        *,
        full_a * least(share_a, share_b) as m_a,
        full_b * least(share_a, share_b) as m_b,
        if(share_a >= share_b, full_a * (share_a - share_b), full_b * (share_b - share_a)) as n_ic,
        if(share_a >= share_b, account_a, account_b) as n_account,
        if(share_a >= share_b, entity_a, entity_b) as n_ic_entity,
        if(share_a >= share_b, entity_b, entity_a) as n_minority_entity,
        if(ic_difference_account != '', -residual_a * share_a, 0) as d_a,
        if(ic_difference_account != '', -residual_b * share_b, 0) as d_b
    from pairs
),

previous as (
    select
        *,
        lagInFrame(m_a, 1, toFloat64(0)) over ({{ to_date }}) as prev_m_a,
        lagInFrame(m_b, 1, toFloat64(0)) over ({{ to_date }}) as prev_m_b,
        lagInFrame(n_ic, 1, toFloat64(0)) over ({{ to_date }}) as prev_n_ic,
        lagInFrame(d_a, 1, toFloat64(0)) over ({{ to_date }}) as prev_d_a,
        lagInFrame(d_b, 1, toFloat64(0)) over ({{ to_date }}) as prev_d_b,
        lagInFrame(difference_cause, 1, '') over ({{ to_date }}) as prev_cause
    from at_basis
),

{# what this period posts #}
posted as (
    select
        *,
        m_a - if(basis = 'balance', prev_m_a, 0) as post_m_a,
        m_b - if(basis = 'balance', prev_m_b, 0) as post_m_b,
        n_ic - if(basis = 'balance', prev_n_ic, 0) as post_n,
        d_a - if(basis = 'balance', prev_d_a, 0) as post_d_a,
        d_b - if(basis = 'balance', prev_d_b, 0) as post_d_b,
        {# a balance-sheet difference reversed once the pair agrees (cause now
           'none') keeps the label of the difference it reverses #}
        if(difference_cause = 'none', prev_cause, difference_cause) as posted_cause
    from previous
),

{# (account, entity, amount) for each of an entry's two legs #}
entries as (
    select 'matched' as elimination_kind, '' as cause,
           account_a as acc1, entity_a as ent1, post_m_a as v1, account_b as acc2, entity_b as ent2,
           consolidation_group, fiscal_year, fiscal_period, basis, entity_a, account_a, entity_b, account_b
    from posted
    where abs(post_m_a) >= 0.005

    union all

    select 'nci', '',
           n_account, n_ic_entity, post_n, '{{ ic_nci_account() }}', n_minority_entity,
           consolidation_group, fiscal_year, fiscal_period, basis, entity_a, account_a, entity_b, account_b
    from posted
    where abs(post_n) >= 0.005

    union all

    select 'difference', posted_cause,
           account_a, entity_a, post_d_a, ic_difference_account, entity_b,
           consolidation_group, fiscal_year, fiscal_period, basis, entity_a, account_a, entity_b, account_b
    from posted
    where ic_difference_account != '' and abs(post_d_a) >= 0.005

    union all

    select 'difference', posted_cause,
           account_b, entity_b, post_d_b, ic_difference_account, entity_a,
           consolidation_group, fiscal_year, fiscal_period, basis, entity_a, account_a, entity_b, account_b
    from posted
    where ic_difference_account != '' and abs(post_d_b) >= 0.005
),

balance_eliminations as (
    select
        concat('IC:', account_a, '/', account_b) as rule_id,
        concat('Intercompany: ', elimination_kind) as rule_name,
        'balance' as rule_type,
        consolidation_group,
        fiscal_year,
        fiscal_period,
        {# the second leg is the negative of the first: the leg that reduces
           its account is the debit_* one #}
        if(v1 <= 0, acc1, acc2) as debit_account,
        if(v1 <= 0, acc2, acc1) as credit_account,
        if(v1 <= 0, ent1, ent2) as debit_entity,
        if(v1 <= 0, ent2, ent1) as credit_entity,
        abs(v1) as elimination_amount,
        -abs(v1) as debit_elimination,
        abs(v1) as credit_elimination,
        elimination_kind,
        cause as difference_cause,
        basis,
        entity_a,
        account_a,
        entity_b,
        account_b
    from entries
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
        '' as difference_cause,
        '' as basis,
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

select * from balance_eliminations
union all
select * from unrealized_profit_eliminations
