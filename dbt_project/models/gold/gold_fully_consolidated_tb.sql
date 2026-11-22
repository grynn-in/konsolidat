{# Round 5, F5: layer 2's one-representation-per-leg choice compares a side's
   gross against the LEG's amount, i.e. a non-equality across both sides of the
   join. ClickHouse refuses that in an ON clause unless
   allow_experimental_join_condition is set — and gold_ic_eliminations, one
   model upstream in this same chain, already sets it
   (gold_ic_eliminations.sql:3). An earlier commit called the refusal a hard
   limit and moved the choice into the WHERE. That was wrong, and it mattered:
   in the WHERE a side matching no arm DROPS the leg (fail-silent), while in
   the ON it is a join miss and the whole leg is emitted on a blank slice
   (fail-safe). #}
{{
    config(
        materialized='table',
        engine='MergeTree()',
        order_by='tuple()',
        query_settings={'allow_experimental_join_condition': 1}
    )
}}

{# #154: a TABLE, rebuilt and swapped in on every run. It carries no
   scope_filter/period_filter of its own: its SELECT always reads every upstream
   row (konsolidat#124), so a scoped close re-derived it in full anyway. As
   delete+insert it only replaced the keys the SELECT produced, and a key that
   left it (an entity that stopped consolidating) kept its rows forever. #}

{# PRD-5 R4: Unified consolidated trial balance
   Unions: entity balances + IC eliminations + CTA + topside adjustments
   PRD-14: + Layer 5: equity method entries
   PRD-11/12: + Layer 6: acquisition/disposal adjustments
   konsolidat#335: + the ownership exit journal, a branch of layer 6
   konsolidat#316: + Layer 8: journal close (decided 14 Nov 2026 by Deepak Pai, option A;
   design note on #316, chosen under the 5 Nov 2026 standing rule) #}

{# Layer 1: Entity translated balances.
   konsol#159: gold_consolidated_trial_balance has one row per intercompany
   partner. This layer is per account, so it sums over the partners. Passed
   through row by row, gold_consolidated_ytd ran a separate running total
   per partner row (#175 review: 250 instead of 150). #}
with entity_balances as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        account_name,
        {{ dim_select(trailing=true) }}
        reporting_currency,
        sum(group_amount) as amount,
        'entity' as adjustment_type,
        '' as journal_id
    from {{ ref('gold_consolidated_trial_balance') }}
    group by
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        account_name,
        {{ dim_group_by(trailing=true) }}
        reporting_currency
),

{# Layer 2: IC eliminations. Posted in full (IFRS 10.B86(c); konsol#117
   pair 2 K3), so every entry is an ic_elimination with no entity on its legs:
   the minority's share is the NCI line of the NCI movement schedule, not part
   of the elimination. #}
{# konsolidat#245 option C, rewritten after PR #260 review findings F1 and F2.

   A leg of gold_ic_eliminations belongs to ONE SIDE OF ONE PAIR, keyed
   (entity_a, account_a, entity_b, account_b) — the PARTNER is part of that
   key. The first version partitioned only on (group, period, entity,
   account), so a leg was apportioned over everything the entity had booked on
   that account against EVERY partner: review F2 showed a ZZA<->ZZB
   elimination of -600 landing 360 on the slice holding ZZB's balance and 240
   on a slice holding only ZZC's. The account total stayed right and the slices
   were wrong, which no total-based check can see. `partner` is therefore in
   the grain here and in the join.

   TWO CASES, and they must not be confused (review F1). Under
   join_use_nulls=0 a LEFT JOIN miss fills defaults, so `side_mov = 0` was
   true both when no slice row existed AND when the side's slices summed to
   zero. In the second case every one of N slice rows took factor 1.0 and the
   leg was emitted N times at full amount: two offsetting cost centres on one
   intercompany account left the layer out by the whole leg and broke
   assert_ic_elimination_nets_zero. So a side is split only when its movement
   is big enough to divide by; otherwise it collapses to ONE blank-slice row
   carrying the whole leg. `matched` is a sentinel: 0 on a join miss, which
   cannot be confused with a real value. #}
side_slices_by_pair as (
    select
        consolidation_group,
        fiscal_year,
        fiscal_period,
        entity,
        partner,
        account,
        {{ dim_select(trailing=true) }}
        sum(mov_group) as slice_mov,
        sum(sum(mov_group)) over (
            partition by consolidation_group, fiscal_year, fiscal_period,
                         entity, partner, account
        ) as side_mov
    from {{ ref('gold_ic_side_slices') }}
    group by consolidation_group, fiscal_year, fiscal_period, entity, partner, account
             {{ dim_group_by(leading=true) }}
),

{# ALIGNED gross, in its own pass: only the slices pointing the same way as the
   side's net (decision 2B). A slice holding an opposite-signed balance
   contributes nothing to the base and takes no share. Magnitude weighting,
   which this replaces, gave such a slice an elimination of the leg's sign and
   pushed it further from its own balance; it now receives nothing.

   CORRECTION (round 5, F2): an earlier version of this note added "so no slice
   is ever moved away from zero". That is FALSE — it holds only when the leg
   opposes the side's net, and nothing guarantees that. When a side settles
   while its partner catches up, the leg shares the side's sign and every
   aligned slice is pushed further from zero. What 2B guarantees is narrower
   and still worth having: a slice OPPOSING its side takes nothing, and with
   leg_coverage() = 1.0 no slice is moved further than it moved itself.

   A SECOND CTE because ClickHouse refuses a window function inside another
   window function (ILLEGAL_AGGREGATION): side_mov is itself a window, so the
   sign it implies cannot be read in the same select. #}
side_slices_aligned as (
    select
        *,
        {# DECLARED DEFAULT (round 5, F6): when side_mov is exactly 0 there is
           no direction in the data, and `>= 0` picks the positive slices. On a
           side of +1000 / -1000 that hands the whole elimination to the
           positive slice; swap them and it goes to the other. The data does not
           decide it, this line does, and the project's standard is that an
           unavoidable default is declared and visible. #}
        sum(greatest(slice_mov * if(side_mov >= 0, 1, -1), 0)) over (
            partition by consolidation_group, fiscal_year, fiscal_period,
                         entity, partner, account
        ) as aligned_gross
    from side_slices_by_pair
),

side_shares_sliced as (
    select
        consolidation_group, fiscal_year, fiscal_period, entity, partner, account,
        {{ dim_select(trailing=true) }}
        greatest(slice_mov * if(side_mov >= 0, 1, -1), 0)
            / nullIf(aligned_gross, 0) as share,
        aligned_gross,
        toUInt8(0) as is_flat,
        toUInt8(1) as matched
    from side_slices_aligned
    where aligned_gross > 0
),

{# And ONE row per side carrying the whole leg, used when the side's activity
   does not cover enough of the leg to divide it (1B), or when there is no
   aligned activity at all. #}
side_shares_whole as (
    select distinct
        consolidation_group, fiscal_year, fiscal_period, entity, partner, account,
        {{ dim_empty_strings(trailing=true) }}
        toFloat64(1) as share,
        aligned_gross,
        toUInt8(1) as is_flat,
        toUInt8(1) as matched
    from side_slices_aligned
),

{# Both representations of every side. Layer 2 picks exactly one per leg, and
   it needs the leg's size to do it, which is why the choice is made at the
   join and not here. #}
side_slice_shares as (
    select * from side_shares_sliced
    union all
    select * from side_shares_whole
),

{# PR #260 review F1: a BALANCE pair's matched leg is split TO DATE.

   gold_ic_eliminations values a balance-sheet pair at its balance to date and
   posts each period the CHANGE in the to-date elimination (decision 14). The
   period path above splits a leg by what each slice MOVED in the period, which
   is the wrong base for a change in a to-date amount:
     (a) the partner books a period late: the side moved nothing in the period
         the leg is posted, so the whole leg fell on the blank slice, and the
         slice holding the balance kept it un-eliminated for ever;
     (b) the side reclassifies its receivable between two slices: the leg is 0,
         so the first slice kept an elimination against a balance it no longer
         holds and the second was never eliminated.
   So for a balance pair's MATCHED leg, the TO-DATE elimination L(t) is split by
   each slice's TO-DATE balance, under the same two rules as the period path
   (2B: only slices aligned with the side's to-date net take a share; 1B: the
   slices must cover leg_coverage() x |L(t)|, else the whole L(t) sits on the
   blank slice), and each period posts the change in each slice's to-date
   share — the to-date difference gold_ic_eliminations takes with lagInFrame
   (bal_posted takes it with arrays; see there). A slice
   whose share falls is posted the reversal even in a period in which the leg
   did not change. assert_ic_slice_to_date_eliminated pins it.

   Movement-basis (P&L) pairs are period-valued and keep the period split. The
   DIFFERENCE legs are not split at all: konsolidat#245 Q1 A (Deepak Pai,
   21 Nov 2026) puts the whole difference entry, both legs, on the blank
   slice (see ic_elims).

   #262: every window here runs over the small per-side grid built from
   gold_ic_side_slices and gold_ic_eliminations, never over the CTB. #}
bal_leg_sides as (
    select consolidation_group, fiscal_year, fiscal_period, rule_id,
           debit_entity as entity, credit_entity as partner, debit_account as account,
           toFloat64(debit_elimination) as leg
    from {{ ref('gold_ic_eliminations') }}
    where basis = 'balance' and elimination_kind = 'matched'
    union all
    select consolidation_group, fiscal_year, fiscal_period, rule_id,
           credit_entity as entity, debit_entity as partner, credit_account as account,
           toFloat64(credit_elimination) as leg
    from {{ ref('gold_ic_eliminations') }}
    where basis = 'balance' and elimination_kind = 'matched'
),

bal_legs as (
    select consolidation_group, fiscal_year, fiscal_period, rule_id, entity, partner, account,
           sum(leg) as leg
    from bal_leg_sides
    group by consolidation_group, fiscal_year, fiscal_period, rule_id, entity, partner, account
),

bal_sides as (
    select distinct consolidation_group, rule_id, entity, partner, account from bal_legs
),

{# the side's slices, per period, for the sides that have a balance leg #}
bal_slices as (
    select
        s.consolidation_group as consolidation_group, s.fiscal_year as fiscal_year,
        s.fiscal_period as fiscal_period, d.rule_id as rule_id,
        s.entity as entity, s.partner as partner, s.account as account,
        {{ dim_select_or_blank('s.', available=var('dimensions'), trailing=true) }}
        sum(s.mov_group) as mov
    from {{ ref('gold_ic_side_slices') }} as s
    inner join bal_sides as d
        on d.consolidation_group = s.consolidation_group and d.entity = s.entity
        and d.partner = s.partner and d.account = s.account
    group by s.consolidation_group, s.fiscal_year, s.fiscal_period, d.rule_id,
             s.entity, s.partner, s.account
             {{ dim_group_by('s.', leading=true) }}
),

{# every period in which the side's leg or any of its slices changes #}
bal_grid as (
    select distinct consolidation_group, fiscal_year, fiscal_period, rule_id, entity, partner, account
    from (
        select consolidation_group, fiscal_year, fiscal_period, rule_id, entity, partner, account from bal_legs
        union all
        select consolidation_group, fiscal_year, fiscal_period, rule_id, entity, partner, account from bal_slices
    )
),

{# L(t), the side's matched elimination to date. join_use_nulls=0: a grid
   period with no leg row fills 0, which is what it posted. #}
bal_leg_to_date as (
    select
        g.consolidation_group as consolidation_group, g.fiscal_year as fiscal_year,
        g.fiscal_period as fiscal_period, g.rule_id as rule_id,
        g.entity as entity, g.partner as partner, g.account as account,
        sum(l.leg) over (
            partition by g.consolidation_group, g.rule_id, g.entity, g.partner, g.account
            order by g.fiscal_year, g.fiscal_period
            rows between unbounded preceding and current row
        ) as leg_td
    from bal_grid as g
    left join bal_legs as l
        on l.consolidation_group = g.consolidation_group and l.fiscal_year = g.fiscal_year
        and l.fiscal_period = g.fiscal_period and l.rule_id = g.rule_id
        and l.entity = g.entity and l.partner = g.partner and l.account = g.account
),

bal_slice_keys as (
    select distinct consolidation_group, rule_id, entity, partner, account
           {{ dim_select(leading=true) }}
    from bal_slices
),

{# each slice at every grid period of its side, so its to-date balance is
   carried through the periods it did not move in #}
bal_slice_grid as (
    select
        g.consolidation_group as consolidation_group, g.fiscal_year as fiscal_year,
        g.fiscal_period as fiscal_period, g.rule_id as rule_id,
        g.entity as entity, g.partner as partner, g.account as account,
        {{ dim_select_or_blank('k.', available=var('dimensions'), trailing=true) }}
        sum(m.mov) over (
            partition by g.consolidation_group, g.rule_id, g.entity, g.partner, g.account
                         {{ dim_group_by('k.', leading=true) }}
            order by g.fiscal_year, g.fiscal_period
            rows between unbounded preceding and current row
        ) as bal_td
    from bal_grid as g
    inner join bal_slice_keys as k
        on k.consolidation_group = g.consolidation_group and k.rule_id = g.rule_id
        and k.entity = g.entity and k.partner = g.partner and k.account = g.account
    left join bal_slices as m
        on m.consolidation_group = g.consolidation_group and m.fiscal_year = g.fiscal_year
        and m.fiscal_period = g.fiscal_period and m.rule_id = g.rule_id
        and m.entity = g.entity and m.partner = g.partner and m.account = g.account
        {% for d in var('dimensions') %}
        and m.{{ d.name }} = k.{{ d.name }}
        {%- endfor %}
),

{# separate passes: ClickHouse refuses a window inside a window #}
bal_slice_side as (
    select
        *,
        sum(bal_td) over (
            partition by consolidation_group, fiscal_year, fiscal_period, rule_id, entity, partner, account
        ) as side_td
    from bal_slice_grid
),

bal_slice_aligned as (
    select
        *,
        {# side_td = 0 picks the positive slices: the declared default of the
           period path (round 5, F6), applied to date #}
        greatest(bal_td * if(side_td >= 0, 1, -1), 0) as aligned_s
    from bal_slice_side
),

bal_gross as (
    select consolidation_group, fiscal_year, fiscal_period, rule_id, entity, partner, account,
           sum(aligned_s) as aligned_gross
    from bal_slice_aligned
    group by consolidation_group, fiscal_year, fiscal_period, rule_id, entity, partner, account
),

{# 1B, to date: split only when the aligned slices cover the to-date leg. A side
   with no slice row is a join miss, aligned_gross 0: not split. #}
bal_cover as (
    select
        l.consolidation_group as consolidation_group, l.fiscal_year as fiscal_year,
        l.fiscal_period as fiscal_period, l.rule_id as rule_id,
        l.entity as entity, l.partner as partner, l.account as account,
        l.leg_td as leg_td, g.aligned_gross as aligned_gross,
        toUInt8(g.aligned_gross > 0 and g.aligned_gross >= {{ leg_coverage() }} * abs(l.leg_td)) as split
    from bal_leg_to_date as l
    left join bal_gross as g
        on g.consolidation_group = l.consolidation_group and g.fiscal_year = l.fiscal_year
        and g.fiscal_period = l.fiscal_period and g.rule_id = l.rule_id
        and g.entity = l.entity and g.partner = l.partner and g.account = l.account
),

{# each slice's share of L(t), and the whole-leg row on the blank slice #}
bal_to_date as (
    select
        a.consolidation_group as consolidation_group, a.fiscal_year as fiscal_year,
        a.fiscal_period as fiscal_period, a.rule_id as rule_id,
        a.entity as entity, a.partner as partner, a.account as account,
        toUInt8(0) as is_whole,
        {{ dim_select_or_blank('a.', available=var('dimensions'), trailing=true) }}
        if(c.split = 1, c.leg_td * a.aligned_s / c.aligned_gross, 0) as elim_td
    from bal_slice_aligned as a
    inner join bal_cover as c
        on c.consolidation_group = a.consolidation_group and c.fiscal_year = a.fiscal_year
        and c.fiscal_period = a.fiscal_period and c.rule_id = a.rule_id
        and c.entity = a.entity and c.partner = a.partner and c.account = a.account
    union all
    select
        consolidation_group, fiscal_year, fiscal_period, rule_id, entity, partner, account,
        toUInt8(1) as is_whole,
        {{ dim_empty_strings(trailing=true) }}
        if(split = 1, 0, leg_td) as elim_td
    from bal_cover
),

{# what each period posts: the change in the slice's to-date share.
   An array difference, not lagInFrame: ClickHouse 24.8 is killed (out of
   memory, nothing logged; exit 137) running a window over bal_to_date when
   the IC inputs are empty and max_threads > 2, which is every first build on
   a fresh site and the zero-dimension CI build (#260 CI, 16 Nov 2026). The
   grid is distinct per (key, year, period), so the previous array element is
   the row lagInFrame would read, and the first period posts its whole share. #}
bal_posted as (
    select
        consolidation_group, rule_id, entity, partner, account, is_whole,
        {{ dim_select(trailing=true) }}
        p.1 as fiscal_year, p.2 as fiscal_period, p.3 as elim_td, p.4 as posted
    from (
        select
            consolidation_group, rule_id, entity, partner, account, is_whole,
            {{ dim_select(trailing=true) }}
            arraySort(x -> (x.1, x.2), groupArray((fiscal_year, fiscal_period, elim_td))) as s,
            arrayJoin(arrayMap(
                i -> (s[i].1, s[i].2, s[i].3, s[i].3 - if(i = 1, toFloat64(0), s[i - 1].3)),
                arrayEnumerate(s))) as p
        from bal_to_date
        group by consolidation_group, rule_id, entity, partner, account, is_whole
                 {{ dim_group_by(leading=true) }}
    )
),

ic_elims as (

{# konsolidat#245 layer 2, option C (Deepak Pai, 6 Oct 2026): each leg carries
   ITS OWN side's slice, for the MATCHED part only: the difference entry (the
   unmatched residual) stays on the blank slice on both legs (Q1 A, 21 Nov 2026;
   rejected: B, slicing its IC-account leg by the matched part's mix). The
   matched leg's amount is split across that side's dimension
   values in proportion to what the side booked (gold_ic_side_slices), so the
   per-slice amounts sum to exactly the leg's elimination — Sum(slice_mov)/side_mov
   is 1 by construction, and assert_ic_side_slices_sum_to_the_side guards that
   identity. A side with no slice information (nothing booked, so the ratio is
   undefined) keeps the whole leg on a blank slice rather than inventing one.

   The split is HERE and not in gold_ic_eliminations because that model carries
   both legs on one row: splitting there would need a cross product of the two
   sides' slices, which is not what either leg eliminates. Layer 2 has already
   separated the legs, so each can be split against its own side. That also
   leaves gold_ic_eliminations, its ten singular tests and its documented
   "every row nets to zero" invariant completely untouched. #}
    select
        e.consolidation_group as consolidation_group,
        '' as data_area_id,
        e.fiscal_year as fiscal_year,
        e.fiscal_period as fiscal_period,
        e.debit_account as main_account,
        'IC Elimination' as account_name,
        {{ dim_select_or_blank('sl.', available=var('dimensions'), trailing=true) }}
        '' as reporting_currency,
        {# the leg, apportioned to this slice; the whole leg when the side
           booked nothing to apportion over #}
        {# matched = 0 is a join miss (join_use_nulls=0 gives defaults, never
           NULL), and then the whole leg lands on a blank slice.

           (The NCI legs this note once discussed are retired: IC is eliminated
           in full, konsol#117 pair 2 K3, so every leg is an ic_elimination.)

           The fallback is still SILENT, and it has THREE causes the output
           cannot tell apart (round 4, F6 — the previous note said two):
             1. a join miss, this branch;
             2. a side whose gross is below materiality, the flat branch;
             3. a GENUINE slice whose declared dimension value is blank —
                gold_ic_side_slices takes dim_select straight from the
                consolidated TB, where an unset dimension is '' and not NULL.
           Cause 3 is the only one live produces, because every dimension
           column on this site is blank. Naming them needs a reason column on
           the layer, which is not in this change. #}
        e.debit_elimination * if(sl.matched = 0, 1.0, sl.share) as amount,
        'ic_elimination' as adjustment_type,
        e.rule_id as journal_id
    from {{ ref('gold_ic_eliminations') }} as e
    left join side_slice_shares as sl
        on sl.consolidation_group = e.consolidation_group
        and sl.fiscal_year = e.fiscal_year
        and sl.fiscal_period = e.fiscal_period
        and sl.entity = e.debit_entity
        and sl.partner = e.credit_entity
        and sl.account = e.debit_account
        {# ONE representation of the side per leg (1B): its own activity must
           cover the whole leg before its slices divide it, else the single
           whole-leg row. In the ON, so a side matching neither arm is a join
           miss and the leg is still emitted (fail-safe) rather than dropped. #}
        and (sl.is_flat = 0
             and sl.aligned_gross >= {{ leg_coverage() }} * abs(e.debit_elimination)
             or sl.is_flat = 1
             and sl.aligned_gross <  {{ leg_coverage() }} * abs(e.debit_elimination))
        {# konsolidat#245 Q1 A (Deepak Pai, 21 Nov 2026): the DIFFERENCE entry, both
           legs, is never split: a join miss, so it lands whole on the blank slice.
           assert_ic_difference_on_the_blank_slice pins it. #}
        and e.elimination_kind != 'difference'
    {# a balance pair's MATCHED leg is split to date, in bal_posted above #}
    where not (e.basis = 'balance' and e.elimination_kind = 'matched')


    union all

    select
        e.consolidation_group as consolidation_group,
        '' as data_area_id,
        e.fiscal_year as fiscal_year,
        e.fiscal_period as fiscal_period,
        e.credit_account as main_account,
        'IC Elimination' as account_name,
        {{ dim_select_or_blank('sl.', available=var('dimensions'), trailing=true) }}
        '' as reporting_currency,
        e.credit_elimination * if(sl.matched = 0, 1.0, sl.share) as amount,
        'ic_elimination' as adjustment_type,
        e.rule_id as journal_id
    from {{ ref('gold_ic_eliminations') }} as e
    left join side_slice_shares as sl
        on sl.consolidation_group = e.consolidation_group
        and sl.fiscal_year = e.fiscal_year
        and sl.fiscal_period = e.fiscal_period
        and sl.entity = e.credit_entity
        and sl.partner = e.debit_entity
        and sl.account = e.credit_account
        {# ONE representation of the side per leg (1B): its own activity must
           cover the whole leg before its slices divide it, else the single
           whole-leg row. In the ON, so a side matching neither arm is a join
           miss and the leg is still emitted (fail-safe) rather than dropped. #}
        and (sl.is_flat = 0
             and sl.aligned_gross >= {{ leg_coverage() }} * abs(e.credit_elimination)
             or sl.is_flat = 1
             and sl.aligned_gross <  {{ leg_coverage() }} * abs(e.credit_elimination))
        {# konsolidat#245 Q1 A (Deepak Pai, 21 Nov 2026): the DIFFERENCE entry, both
           legs, is never split: a join miss, so it lands whole on the blank slice.
           assert_ic_difference_on_the_blank_slice pins it. #}
        and e.elimination_kind != 'difference'
    {# a balance pair's MATCHED leg is split to date, in bal_posted above #}
    where not (e.basis = 'balance' and e.elimination_kind = 'matched')

    union all

    {# balance pairs, matched legs: the change in each slice's to-date share #}
    select
        consolidation_group, '' as data_area_id, fiscal_year, fiscal_period,
        account as main_account, 'IC Elimination' as account_name,
        {{ dim_select(trailing=true) }}
        '' as reporting_currency,
        posted as amount,
        'ic_elimination' as adjustment_type,
        rule_id as journal_id
    from bal_posted
    {# a float residue of a zero change is not a posting #}
    where abs(posted) > 1e-9

),

{# Layer 3: CTA entries #}
cta_entries as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        'CTA' as account_name,
        {# konsolidat#245 option D: BLANK BY ARITHMETIC, not by omission. The CTA
           is one plug per entity and period — gold_fx_revaluation computes
           -sum(group_amount) across EVERY account and posts it to a synthetic
           'CTA' account — so it is the residual that makes the entity's
           translated balance sheet balance. It has no slice: a per-dimension
           plug would not be a translation difference, it would be an arbitrary
           allocation of one. assert_sliceless_layers_carry_no_dimension
           asserts this layer stays blank. #}
        {{ dim_empty_strings(trailing=true) }}
        reporting_currency,
        cta_amount as amount,
        'cta' as adjustment_type,
        '' as journal_id
    from {{ ref('gold_fx_revaluation') }}
),

{# Layer 4: Top-side adjustments.
   konsol#305 V03 (P6): summed to the grain assert_journal_grain_unique checks, like layer 6
   (konsolidat#198 J11/J13). Passed through unsummed, two topside lines on one account, entity
   and period (two journals, or a journal next to its konsol#305-D2-11 auto_reversal line) gave
   two rows here — and, downstream, two running totals in gold_consolidated_ytd instead of one.
   journal_id is not part of the grain (a second journal on the same account in the same period
   is one row), so it is reported with any(journal_id), mirroring layer 6. #}
topside as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        any(description) as account_name,
        {# konsolidat#245 option D: a top-side carries the slice its line
           declared, so the dimensions are part of this grain — two lines on one
           account and period with different values are two rows, not one. The
           amount is still a sum, so a finer partition cannot change the total,
           only split it. That is the invariant the A/B asserts. #}
        {{ dim_select(trailing=true) }}
        '' as reporting_currency,
        sum({{ cast_to_float64('net_amount') }}) as amount,
        adjustment_type,
        any(journal_id) as journal_id
    from {{ ref('gold_consolidation_adjustments') }}
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account,
             adjustment_type{{ dim_group_by(leading=true) }}
),

{# Layer 5: Equity method entries (PRD-14) #}
equity_method as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        account_name,
        {# konsolidat#245 option D: BLANK BY DECISION. Settled by Claude on
           6 Oct 2026 under Deepak Pai's instruction to settle it, and decided
           by Deepak Pai on 21 Nov 2026 (Q3 A; rejected: B, inherit the
           associate's slices at the ownership share).

           It COULD inherit: gold_equity_method_associates sums the associate's
           P&L out of gold_trial_balance, which carries real dimension values,
           and sum(per-slice net income) x ownership_pct is arithmetically
           sound. It is left blank because equity income is a ONE-LINE PICKUP
           in the investor's books — "share of profit of associates" — and
           splitting it by the associate's cost centres attributes the
           investor's line to a DIFFERENT entity's management structure,
           importing that entity's dimension vocabulary into the group's.

           Reverse this by replacing the macro with dim_select over the
           associate's slices and removing 'equity_method' from
           assert_sliceless_layers_carry_no_dimension. #}
        {{ dim_empty_strings(trailing=true) }}
        reporting_currency,
        amount,
        'equity_method' as adjustment_type,
        journal_id
    from {{ ref('gold_equity_method_associates') }}
),

{# Layer 7: NCI attribution (konsol#117 pair 2 K2, konsolidat#204 (a)): the minority's
   share of a full-method subsidiary's result and CTA, one balanced journal per
   (group, entity, period). konsolidat#245 option D: the result legs carry the
   slices of the entity's P&L, the CTA legs are blank (gold_nci_attribution_journal). #}
nci_attribution as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        account_name,
        {{ dim_select(trailing=true) }}
        reporting_currency,
        amount,
        adjustment_type,
        journal_id
    from {{ ref('gold_nci_attribution_journal') }}
),

{# Layer 6: Acquisition & disposal adjustments (PRD-11/12).
   #175 re-review F3: the pnl_proration rows are one per consolidated row,
   and gold_consolidated_trial_balance has a row per intercompany partner,
   so they are summed to the account grain here, like layer 1 (the
   proration rows inherit the dimensions of their source row, review F1; the
   partner is summed away). Otherwise
   gold_consolidated_ytd ran a separate running total per row.
   konsolidat#198: the goodwill and fair-value lines come from the balanced
   acquisition journal (gold_business_combination_journal, posted from the
   submitted Business Combination), not from gold_acquisition_adjustments,
   which keeps only the partial-period P&L adjustment (#171 2c: it follows
   the group's declared partial_period_treatment, and its balancing line sits
   on the retained-earnings account). Row J5: the monthly goodwill
   amortisation journal (gold_goodwill_amortisation_journal, empty unless the
   group's goodwill_treatment is 'Amortise') joins the layer. Row J6: the
   disposal journal (gold_business_disposal_journal, posted from the
   submitted Business Disposal: derecognition, goodwill, FVA, CTA recycling,
   NCI, proceeds, gain or loss) replaces gold_disposal_adjustments' one-sided
   'DISPOSAL' rows; that model is now empty.
   Row J11 (PR #203 review 7): the journals post several lines to one account
   in one period when the roles differ (the acquisition journal's
   opening_balance and equity_eliminated lines on the same equity account,
   the disposal journal's derecognised and proceeds lines on the same cash
   account), so each journal branch is SUMmed to the account grain
   (group, entity, year, period, account, adjustment_type, journal_id) like
   the proration branch: passed through line by line, gold_consolidated_ytd's
   ROWS window ran a separate running total per line (-687.5, then 0, instead
   of 0). account_role is a line attribute, not part of the grain, and stays
   in the journal models; assert_journal_grain_unique proves the grain.
   Row J13 (PR #203 second review 2): journal_id left the grain too. The YTD
   window partitions by (group, entity, year, account, adjustment_type,
   dimensions) and NOT by journal_id, so two journals of one entity on one
   account in one period (a second deal; an amortisation instalment is a
   different adjustment_type) were two rows under one running total again.
   Each branch now groups without journal_id and emits any(journal_id);
   assert_journal_grain_unique keys on the window's partition columns. #}
acquisition_disposal as (
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        account_name,
        {{ dim_select(trailing=true) }}
        '' as reporting_currency,
        sum(adjustment_amount) as amount,
        adjustment_type,
        concat('ACQ_', data_area_id) as journal_id
    from {{ ref('gold_acquisition_adjustments') }}
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account,
             account_name, adjustment_type{{ dim_group_by(leading=true) }}

    union all

    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        any(account_name) as account_name,
        {{ dim_empty_strings(trailing=true) }}
        '' as reporting_currency,
        sum(adjustment_amount) as amount,
        adjustment_type,
        any(journal_id) as journal_id
    from {{ ref('gold_business_combination_journal') }}
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account,
             adjustment_type

    union all

    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        any(account_name) as account_name,
        {{ dim_empty_strings(trailing=true) }}
        '' as reporting_currency,
        sum(adjustment_amount) as amount,
        adjustment_type,
        any(journal_id) as journal_id
    from {{ ref('gold_goodwill_amortisation_journal') }}
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account,
             adjustment_type

    union all

    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        any(account_name) as account_name,
        {# konsolidat#245 Q2 A (Deepak Pai, 21 Nov 2026): line 105 (post_disposal_pnl)
           carries the slices of the P&L it removes, as pnl_proration does; every
           other disposal line is blank in the journal. #}
        {{ dim_select(trailing=true) }}
        '' as reporting_currency,
        sum(adjustment_amount) as amount,
        adjustment_type,
        any(journal_id) as journal_id
    from {{ ref('gold_business_disposal_journal') }}
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account,
             adjustment_type{{ dim_group_by(leading=true) }}

    union all

    {# konsolidat#335 option A (decided 14 Nov 2026, Deepak Pai), task X3: the ownership exit journal
       (gold_ownership_exit_journal, adjustment_type 'ownership_exit'): an Ownership Period that ends without
       a Business Disposal derecognises the entity's carried balances, beside the disposal journal and summed
       to the same grain (row J11/J13). #}
    select
        consolidation_group,
        data_area_id,
        fiscal_year,
        fiscal_period,
        main_account,
        any(account_name) as account_name,
        {{ dim_empty_strings(trailing=true) }}
        '' as reporting_currency,
        sum(adjustment_amount) as amount,
        adjustment_type,
        any(journal_id) as journal_id
    from {{ ref('gold_ownership_exit_journal') }}
    group by consolidation_group, data_area_id, fiscal_year, fiscal_period, main_account,
             adjustment_type
),

{# Union of the posted layers (every layer except the close itself) #}
posted_layers as (
    select * from entity_balances
    union all
    select * from ic_elims
    union all
    select * from cta_entries
    union all
    select * from topside
    union all
    select * from equity_method
    union all
    select * from acquisition_disposal
    union all
    select * from nci_attribution
),

{# Layer 8: journal close (konsolidat#316, decided 14 Nov 2026 by Deepak Pai: option A, one
   journal_close layer in this model; rejected B, each journal closes its own lines, and C, close
   at report time). Design note on #316, chosen under the 5 Nov 2026 standing rule.
   In each fiscal year's Closing period (the first period_type = 'Closing' of the year in
   fiscal_periods, as silver_tb_movements finds it) the year's P&L of every journal layer not in
   journal_close_excluded_layers() (entity: the #259 close; ic_elimination: reverses its own P&L
   legs) moves into retained_earnings_account(). P&L = silver_main_accounts.is_pnl = 1, or a
   pseudo-account in journal_pnl_pseudo_accounts() (EQ_INCOME). Summed over the year's periods up
   to AND including the Closing period; postings after it are not closed (the year-end test names
   them, reason after_closing).
   The year rule is the #259 entity close's (#357 review F2, re-review R1; chosen under the 5 Nov 2026
   standing rule: the journal close follows the #259 entity close): a (group, fiscal year) is closed
   only when a LATER fiscal year exists in the group's ENTITY layer, the members' own TB rows
   (journal_close_years(), shared with the year-end test). A journal posting into a later year (a
   topside auto-reversing into next year's P1) does not close a year: until a member files the later
   year #259 leaves the entity P&L open (silver_tb_movements years_to_close: fiscal_year < last_year),
   and so the journal P&L stays open beside it. Residual: a group of members that post no entity rows
   for the later year (only associates, or only deal journals) is not closed until one does.
   Lines are rounded to 4 places (journals are kept to 4 places, #353; re-review R2), so Float dust
   (0.1 + 0.2 - 0.3) posts no line.
   One negating line per (group, entity, year, account, dimensions) and one retained-earnings
   line per (group, entity, year, dimensions); no partner (this table has none). When the chart
   flags not exactly one retained-earnings account, nothing is posted:
   assert_retained_earnings_account_unique fails naming the group. Reads posted_layers, never this
   model, so there is no cycle. #}
journal_close_periods as (
    select fiscal_year, min(fiscal_period) as closing_period
    from {{ source('epm_staging', 'fiscal_periods') }}
    where period_type = 'Closing'
    group by fiscal_year
),

journal_close_source as (
    select
        l.consolidation_group as consolidation_group,
        l.data_area_id as data_area_id,
        l.fiscal_year as fiscal_year,
        c.closing_period as closing_period,
        l.main_account as main_account,
        {# aliased: dim_select(prefix=) leaves the column named `l.<dim>` #}
        {% for d in get_dimensions() -%}
        l.{{ d.name }} as {{ d.name }},
        {% endfor -%}
        l.amount as amount
    from posted_layers as l
    inner join journal_close_periods as c on c.fiscal_year = l.fiscal_year
    inner join {{ journal_close_years() }} as y on y.consolidation_group = l.consolidation_group
    left join {{ ref('silver_main_accounts') }} as ma on ma.main_account_id = l.main_account
    where l.fiscal_year < y.last_year
      and l.adjustment_type not in ({{ "'" ~ journal_close_excluded_layers() | join("','") ~ "'" }})
      and l.fiscal_period <= c.closing_period
      and (ma.is_pnl = 1
           or l.main_account in ({{ "'" ~ journal_pnl_pseudo_accounts() | join("','") ~ "'" }}))
),

{# Per-account lines: one per (group, entity, year, account, dimensions) whose year P&L, rounded to 4
   places, is not 0 (#357 review F5: a topside and its auto-reversal that net to 0 post no line;
   re-review R2: Float dust rounds to 0 and posts no line). #}
journal_close_lines as (
    select
        s.consolidation_group as consolidation_group,
        s.data_area_id as data_area_id,
        s.fiscal_year as fiscal_year,
        s.closing_period as fiscal_period,
        s.main_account as main_account,
        {# aliased: dim_select(prefix=) leaves the column named `s.<dim>` #}
        {% for d in get_dimensions() -%}
        s.{{ d.name }} as {{ d.name }},
        {% endfor -%}
        round(-sum(s.amount), 4) as amount
    from journal_close_source as s
    cross join {{ retained_earnings_account() }} as re
    where re.re_count = 1
    group by s.consolidation_group, s.data_area_id, s.fiscal_year, s.closing_period,
             s.main_account{{ dim_group_by(prefix='s.', leading=true) }}
    having round(sum(s.amount), 4) != 0
),

{# The retained-earnings line is minus the sum of the KEPT, rounded lines, itself rounded to 4 places,
   so the journal balances to 4 places by construction; a dropped line rounds to 0. #}
journal_close as (
    select
        l.consolidation_group as consolidation_group,
        l.data_area_id as data_area_id,
        l.fiscal_year as fiscal_year,
        l.fiscal_period as fiscal_period,
        l.main_account as main_account,
        'Journal close' as account_name,
        {% for d in get_dimensions() -%}
        l.{{ d.name }} as {{ d.name }},
        {% endfor -%}
        '' as reporting_currency,
        l.amount as amount,
        'journal_close' as adjustment_type,
        concat('JCLOSE_', l.consolidation_group, '_', toString(l.fiscal_year)) as journal_id
    from journal_close_lines as l

    union all

    select
        l.consolidation_group as consolidation_group,
        l.data_area_id as data_area_id,
        l.fiscal_year as fiscal_year,
        l.fiscal_period as fiscal_period,
        any(re.retained_earnings_account) as main_account,
        'Journal close' as account_name,
        {% for d in get_dimensions() -%}
        l.{{ d.name }} as {{ d.name }},
        {% endfor -%}
        '' as reporting_currency,
        round(-sum(l.amount), 4) as amount,
        'journal_close' as adjustment_type,
        concat('JCLOSE_', l.consolidation_group, '_', toString(l.fiscal_year)) as journal_id
    from journal_close_lines as l
    cross join {{ retained_earnings_account() }} as re
    where re.re_count = 1
    group by l.consolidation_group, l.data_area_id, l.fiscal_year,
             l.fiscal_period{{ dim_group_by(prefix='l.', leading=true) }}
    having round(sum(l.amount), 4) != 0
),

{# Union all layers #}
all_layers as (
    select * from posted_layers
    union all
    select * from journal_close
)

select * from all_layers
