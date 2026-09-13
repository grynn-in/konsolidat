{{
    config(
        query_settings={'allow_experimental_join_condition': 1},
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# Intercompany elimination entries. Each row is one two-legged entry:
   debit_account takes debit_elimination (<= 0) and credit_account takes
   credit_elimination (>= 0), so every row nets to zero.

   konsolidat#148: this used to sum each entity's WHOLE balance per account,
   then join every ordered debit-entity x credit-entity pair and eliminate the
   lesser balance for each: 2.61M eliminated against a 2.56M intercompany
   revenue balance. It had no counterparty to pair on.

   Two views (elimination_view):
   - 'group': the group view, the one gold_fully_consolidated_tb books. It
     presents each entity at the share the group holds (group_amount).
   - 'nci': the NCI view, the minority owners' share of each line
     (gold_consolidated_trial_balance.nci_amount), which the consolidation
     report adds to the group view for its 100% column (#175 re-review H1).
   Group plus NCI is the full (100%) consolidation. In it both sides of a
   pair are eliminated in full, a difference is booked at 100%, and the NCI
   line nets to zero per group and period (assert_ic_nci_line_nets_zero).
   Not per entity: its legs are attributed to the entity whose minority owns
   them (assert_ic_nci_leg_entity), and with sides held at 70% and 80% those
   differ.

   Balance eliminations come from gold_ic_reconciliation, one row per pair and
   period (decided 13 Sep 2026):
   - 'matched' (group view): the matched amount (the smaller side, at 100%),
     eliminated from both sides at the share of it both hold,
     least(share_a, share_b).
   - 'nci' (group view, decision 12): the side the group holds more of (for
     example the 100%-owned entity against an 80%-owned one) is eliminated at
     its own share. The rest of it goes to the NCI line (ic_nci_account()),
     attributed to the other, partly owned side's entity, whose minority
     owners hold that share; never to the difference account. Each side's
     entry is computed and posted on its own account (re-review L1). With
     1000 against 1000 at 100% and 80%, the group view eliminates 1000 and
     800 and puts +200 to NCI.
   - 'difference' (group view): what is left of each side after that (the
     100% residual) at the side's share, moved to the group's
     intercompany-difference account and labelled with the pair's
     difference_cause (decision 13). A group without one books no
     difference; the rest stays on the IC accounts.
   - 'matched' and 'difference' (NCI view): the same eliminations for the
     minority's share of each side, at (1 - share), against the NCI line.
     In the example, B's minority holds -200 of the payable: +200 on it,
     -200 to the NCI line. Nothing is posted for a 100%-owned side.
   - Decision 14: a balance-sheet pair is valued at its balance to date, so
     the amounts above are eliminations TO DATE. The views hold movements, so
     each period posts the change since the pair's previous row: a timing
     difference booked in one period is reversed in the period the partner
     catches up, and everything is reversed in the 'left' row after a partner
     leaves the group. A P&L pair is valued at the period's movement and
     posts it as it is.
   - Rows without a partner are never eliminated (gold_ic_unmatched).
     Balance-type IC Elimination Rules no longer eliminate anything. The
     doctype stays for special cases: 'unrealized_profit' below (group view). #}

{% set pair = "consolidation_group, entity_a, account_a, entity_b, account_b" %}
{% set to_date = "partition by " ~ pair ~ " order by fiscal_year, fiscal_period rows between unbounded preceding and current row" %}
{% set components = ['m_a', 'm_b', 'n_a', 'n_b', 'd_a', 'd_b', 'v_m_a', 'v_m_b', 'v_d_a', 'v_d_b'] %}

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
        {# group view #}
        full_a * least(share_a, share_b) as m_a,
        full_b * least(share_a, share_b) as m_b,
        if(share_a > share_b, full_a * (share_a - share_b), 0) as n_a,
        if(share_b > share_a, full_b * (share_b - share_a), 0) as n_b,
        if(ic_difference_account != '', -residual_a * share_a, 0) as d_a,
        if(ic_difference_account != '', -residual_b * share_b, 0) as d_b,
        {# NCI view: the minority's share of each side #}
        full_a * (1 - share_a) as v_m_a,
        full_b * (1 - share_b) as v_m_b,
        if(ic_difference_account != '', -residual_a * (1 - share_a), 0) as v_d_a,
        if(ic_difference_account != '', -residual_b * (1 - share_b), 0) as v_d_b
    from pairs
),

previous as (
    select
        *,
        {% for c in components %}
        lagInFrame(toFloat64({{ c }}), 1, toFloat64(0)) over ({{ to_date }}) as prev_{{ c }},
        {% endfor %}
        lagInFrame(difference_cause, 1, '') over ({{ to_date }}) as prev_cause
    from at_basis
),

{# what this period posts #}
posted as (
    select
        *,
        {% for c in components %}
        toFloat64({{ c }}) - if(basis = 'balance', prev_{{ c }}, 0) as post_{{ c }},
        {% endfor %}
        {# a difference reversed once the pair agrees, or leaves the group
           (cause now 'none'), keeps the label of the difference it reverses #}
        if(difference_cause = 'none', prev_cause, difference_cause) as posted_cause
    from previous
),

{# (account, entity, amount) for each of an entry's two legs. The NCI-line
   legs below (group 'nci', NCI view 'matched') net to zero per group and
   period, not per entity: the group view's is attributed to the other,
   partly owned side, the NCI view's to its own side. #}
{% set legs = [
    ('group', 'matched', "''",           'account_a', 'entity_a', 'post_m_a',   'account_b',             'entity_b', 'abs(post_m_a) >= 0.005'),
    ('group', 'nci',     "''",           'account_a', 'entity_a', 'post_n_a',   "'" ~ ic_nci_account() ~ "'", 'entity_b', 'abs(post_n_a) >= 0.005'),
    ('group', 'nci',     "''",           'account_b', 'entity_b', 'post_n_b',   "'" ~ ic_nci_account() ~ "'", 'entity_a', 'abs(post_n_b) >= 0.005'),
    ('group', 'difference', 'posted_cause', 'account_a', 'entity_a', 'post_d_a', 'ic_difference_account', 'entity_b', "ic_difference_account != '' and abs(post_d_a) >= 0.005"),
    ('group', 'difference', 'posted_cause', 'account_b', 'entity_b', 'post_d_b', 'ic_difference_account', 'entity_a', "ic_difference_account != '' and abs(post_d_b) >= 0.005"),
    ('nci',   'matched', "''",           'account_a', 'entity_a', 'post_v_m_a', "'" ~ ic_nci_account() ~ "'", 'entity_a', 'abs(post_v_m_a) >= 0.005'),
    ('nci',   'matched', "''",           'account_b', 'entity_b', 'post_v_m_b', "'" ~ ic_nci_account() ~ "'", 'entity_b', 'abs(post_v_m_b) >= 0.005'),
    ('nci',   'difference', 'posted_cause', 'account_a', 'entity_a', 'post_v_d_a', 'ic_difference_account', 'entity_a', "ic_difference_account != '' and abs(post_v_d_a) >= 0.005"),
    ('nci',   'difference', 'posted_cause', 'account_b', 'entity_b', 'post_v_d_b', 'ic_difference_account', 'entity_b', "ic_difference_account != '' and abs(post_v_d_b) >= 0.005"),
] %}
entries as (
    {% for view, kind, cause, acc1, ent1, amount, acc2, ent2, cond in legs %}
    select '{{ view }}' as elimination_view, '{{ kind }}' as elimination_kind, {{ cause }} as cause,
           {{ acc1 }} as acc1, {{ ent1 }} as ent1, {{ amount }} as v1, {{ acc2 }} as acc2, {{ ent2 }} as ent2,
           consolidation_group, fiscal_year, fiscal_period, basis, entity_a, account_a, entity_b, account_b
    from posted
    where {{ cond }}
    {% if not loop.last %}union all{% endif %}
    {% endfor %}
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
        elimination_view,
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
        'group' as elimination_view,
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
