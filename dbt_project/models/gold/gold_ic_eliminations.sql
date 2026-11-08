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

   Posted in full for subsidiaries (IFRS 10.B86(c)), at the operator's share
   where a side is a joint operation (IFRS 11.B34-B37, konsol#117 pair 3).
   Pair 2 K3: IFRS 10.B86(c) eliminates intragroup
   balances, transactions, income and expenses IN FULL, and layer 1 now
   carries a full-method subsidiary at 100% (konsolidat#204 option (a)), so
   both sides of a pair are eliminated at 100% whatever the holding. The
   minority's share of a subsidiary is one NCI line, posted by the attribution
   journal (gold_nci_attribution_journal, K2), not a part of the elimination. This
   supersedes decision 12 (13 Sep 2026: eliminate at the share both sides
   hold, the rest to an NCI leg, and a second 'nci' view for the 100%
   column) by Deepak Pai's decision of 8 Nov 2026 (konsol#117). Every row is
   now in one view, elimination_view = 'group', a column kept for the readers
   that filter on it. assert_ic_eliminated_in_full pins it.

   Pair 3: layer 1 carries a `proportional` entity (an IFRS 11 joint operation)
   at the operator's share, so a transaction with it is eliminated to the
   extent of that interest. One factor per pair, least(share_a, share_b), with
   share = effective_ownership_pct for a `proportional` side and 1.0 otherwise
   (an entity with no ownership row in the group and period keeps 1.0), scales
   the matched legs, the difference legs and the unrealised profit (buyer and
   seller). Pinned by assert_ic_eliminated_in_full and
   assert_unrealized_profit_at_operator_share.

   The difference legs are scaled by the same factor: for S receivable 100 against J (joint operation, 50%) payable 90, the matched 45 is eliminated on both sides,
   S's residual 10 x 0.5 = 5 goes to the difference account, and S keeps 50, 
   the co-operator's share of the receivable, which from the group's view is the external claim whatever J's books say.

   Balance eliminations come from gold_ic_reconciliation, one row per pair and
   period (decided 13 Sep 2026):
   - 'matched': the matched amount (the smaller side, at 100%), eliminated
     from each side in full: full_a from side A, full_b from side B.
   - 'difference': what is left of each side after that (the 100% residual),
     moved to the group's intercompany-difference account and labelled with
     the pair's difference_cause (decision 13). A group without one books no
     difference; the rest stays on the IC accounts.
   - Decision 14: a balance-sheet pair is valued at its balance to date, so
     the amounts above are eliminations TO DATE. The views hold movements, so
     each period posts the change since the pair's previous row: a timing
     difference booked in one period is reversed in the period the partner
     catches up, and everything is reversed in the 'left' row after a partner
     leaves the group. A P&L pair is valued at the period's movement and
     posts it as it is.
   - Rows without a partner are never eliminated (gold_ic_unmatched).
     Balance-type IC Elimination Rules no longer eliminate anything. The
     doctype stays for special cases: 'unrealized_profit' below. #}

{% set pair = "consolidation_group, entity_a, account_a, entity_b, account_b" %}
{% set to_date = "partition by " ~ pair ~ " order by fiscal_year, fiscal_period rows between unbounded preceding and current row" %}
{% set components = ['m_a', 'm_b', 'd_a', 'd_b'] %}

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

{# the pair's factor, IFRS 11.B34-B37. join_use_nulls=0: a miss fills method ''
   and share 0; '' is not 'proportional', so an entity with no ownership row in
   the group and period keeps share 1.0 (today's behaviour) #}
pair_factors as (
    select
        r.consolidation_group as consolidation_group, r.fiscal_year as fiscal_year,
        r.fiscal_period as fiscal_period, r.entity_a as entity_a, r.account_a as account_a,
        r.entity_b as entity_b, r.account_b as account_b,
        least(
            if(oa.consolidation_method = 'proportional', toFloat64(oa.effective_ownership_pct), 1.0),
            if(ob.consolidation_method = 'proportional', toFloat64(ob.effective_ownership_pct), 1.0)
        ) as factor
    from {{ ref('gold_ic_reconciliation') }} as r
    left join {{ ref('gold_entity_ownership') }} as oa
        on oa.consolidation_group = r.consolidation_group and oa.data_area_id = r.entity_a
        and oa.fiscal_year = r.fiscal_year and oa.fiscal_period = r.fiscal_period
    left join {{ ref('gold_entity_ownership') }} as ob
        on ob.consolidation_group = r.consolidation_group and ob.data_area_id = r.entity_b
        and ob.fiscal_year = r.fiscal_year and ob.fiscal_period = r.fiscal_period
),

pairs as (
    select
        r.consolidation_group as consolidation_group, r.fiscal_year as fiscal_year,
        r.fiscal_period as fiscal_period, r.basis as basis,
        r.entity_a as entity_a, r.account_a as account_a, r.entity_b as entity_b, r.account_b as account_b,
        r.ic_difference_account as ic_difference_account, r.difference_cause as difference_cause,
        {# each side's elimination at the pair's factor (1.0 unless a side is a
           joint operation): at 100% it takes the side to its residual #}
        -sign(r.balance_a) * r.matched_amount * f.factor as full_a,
        -sign(r.balance_b) * r.matched_amount * f.factor as full_b,
        r.residual_a as residual_a,
        r.residual_b as residual_b,
        f.factor as factor
    from {{ ref('gold_ic_reconciliation') }} as r
    inner join pair_factors as f
        on f.consolidation_group = r.consolidation_group and f.fiscal_year = r.fiscal_year
        and f.fiscal_period = r.fiscal_period and f.entity_a = r.entity_a and f.account_a = r.account_a
        and f.entity_b = r.entity_b and f.account_b = r.account_b
),

{# every leg on the pair's basis: to date (balance) or for the period (movement) #}
at_basis as (
    select
        *,
        full_a as m_a,
        full_b as m_b,
        if(ic_difference_account != '', -residual_a * factor, 0) as d_a,
        if(ic_difference_account != '', -residual_b * factor, 0) as d_b
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

{# (account, entity, amount) for each of an entry's two legs #}
{% set legs = [
    ('matched',    "''",           'account_a', 'entity_a', 'post_m_a', 'account_b',             'entity_b', 'abs(post_m_a) >= ' ~ materiality_floor()),
    ('difference', 'posted_cause', 'account_a', 'entity_a', 'post_d_a', 'ic_difference_account', 'entity_b', "ic_difference_account != '' and abs(post_d_a) >= " ~ materiality_floor()),
    ('difference', 'posted_cause', 'account_b', 'entity_b', 'post_d_b', 'ic_difference_account', 'entity_a', "ic_difference_account != '' and abs(post_d_b) >= " ~ materiality_floor()),
] %}
entries as (
    {% for kind, cause, acc1, ent1, amount, acc2, ent2, cond in legs %}
    select 'group' as elimination_view, '{{ kind }}' as elimination_kind, {{ cause }} as cause,
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
        icb.ending_inventory_from_ic * (icr.margin_pct / 100.0) * least(
            if(os.consolidation_method = 'proportional', toFloat64(os.effective_ownership_pct), 1.0),
            if(ob.consolidation_method = 'proportional', toFloat64(ob.effective_ownership_pct), 1.0)) as elimination_amount,
        -(icb.ending_inventory_from_ic * (icr.margin_pct / 100.0) * least(
            if(os.consolidation_method = 'proportional', toFloat64(os.effective_ownership_pct), 1.0),
            if(ob.consolidation_method = 'proportional', toFloat64(ob.effective_ownership_pct), 1.0))) as debit_elimination,
        icb.ending_inventory_from_ic * (icr.margin_pct / 100.0) * least(
            if(os.consolidation_method = 'proportional', toFloat64(os.effective_ownership_pct), 1.0),
            if(ob.consolidation_method = 'proportional', toFloat64(ob.effective_ownership_pct), 1.0)) as credit_elimination,
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
    {# the seller's and the buyer's share in this group and period: a joint
       operation on either side limits the elimination to the operator's
       interest (IFRS 11.B34-B37); a miss keeps 1.0 (join_use_nulls=0) #}
    left join {{ ref('gold_entity_ownership') }} as os
        on os.consolidation_group = cg.consolidation_group and os.data_area_id = icb.selling_entity
        and os.fiscal_year = icb.fiscal_year and os.fiscal_period = icb.fiscal_period
    left join {{ ref('gold_entity_ownership') }} as ob
        on ob.consolidation_group = cg.consolidation_group and ob.data_area_id = icb.buying_entity
        and ob.fiscal_year = icb.fiscal_year and ob.fiscal_period = icb.fiscal_period
    where icr.rule_type = 'unrealized_profit'
      and icb.ending_inventory_from_ic > 0
      and icr.margin_pct > 0
      and (icr.debit_entity_pattern = '*' or icb.selling_entity = icr.debit_entity_pattern)
      and (icr.credit_entity_pattern = '*' or icb.buying_entity = icr.credit_entity_pattern)
)

select * from balance_eliminations
union all
select * from unrealized_profit_eliminations
