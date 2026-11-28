-- konsolidat#245 option C, PR #260 review F1. A balance-basis intercompany side
-- is eliminated TO DATE, per slice, in proportion to each slice's TO-DATE balance.
--
-- gold_ic_eliminations values a balance-sheet pair at its balance to date and
-- posts each period the CHANGE in that to-date elimination (decision 14). A
-- slice split by the period's MOVEMENT is therefore the wrong base: when the
-- partner books a period late, the side moved nothing in the period the leg is
-- posted, and the whole leg fell on the blank slice; when the side reclassifies
-- its receivable between two cost centres, the leg is 0 and the first cost
-- centre kept an elimination against a balance it no longer holds. Every
-- per-period check in this layer passes on both, because they compare one
-- period's leg with one period's movement. This test compares CUMULATIVE
-- amounts, which is the only grain where the defect is visible.
--
-- For every balance-basis MATCHED leg side (entity, partner, account) and every
-- period in which that side or its leg changes, the expected to-date
-- elimination on a slice is
--     L(t) x aligned_s(t) / aligned_gross(t)
-- where L(t) is the side's matched elimination to date (the sum of what
-- gold_ic_eliminations posted), aligned_s(t) is the slice's to-date balance when
-- it points the same way as the side's to-date net (decision 2B: an opposing
-- slice takes nothing), and aligned_gross(t) their sum. When aligned_gross does
-- not cover leg_coverage() x |L(t)| (decision 1B), the whole L(t) is expected on
-- the blank slice instead. Coverage is decided at the group currency's ISO
-- minor unit, through ic_leg_covered(), the macro the model uses (konsolidat#395,
-- option B, Deepak Pai, 27 Nov 2026). Expected amounts
-- are summed over every side that shares the account, and compared with the
-- cumulative ic_elimination rows of gold_fully_consolidated_tb on that account
-- and slice.
--
-- Out of scope, on purpose: an account that ever carries a DIFFERENCE leg. Its
-- blank-slice difference would mix into the cumulative amounts compared here.
-- Since konsolidat#245 Q1 A (Deepak Pai, 21 Nov 2026) the difference entry sits
-- on the blank slice on both legs; assert_ic_difference_on_the_blank_slice
-- asserts that. Movement-basis (P&L) pairs are period-valued and are covered
-- by assert_ic_slice_not_moved_past_its_own.
--
-- Error severity: a slice left with an elimination it no longer holds is a
-- wrong consolidated number that every total-based check accepts.
{% set floor = materiality_floor() %}

with leg_sides as (
    select consolidation_group, fiscal_year * 100 + fiscal_period as pk,
           debit_entity as entity, credit_entity as partner, debit_account as account,
           toFloat64(debit_elimination) as leg
    from {{ ref('gold_ic_eliminations') }}
    where elimination_view = 'group' and basis = 'balance' and elimination_kind = 'matched'
    union all
    select consolidation_group, fiscal_year * 100 + fiscal_period as pk,
           credit_entity as entity, debit_entity as partner, credit_account as account,
           toFloat64(credit_elimination) as leg
    from {{ ref('gold_ic_eliminations') }}
    where elimination_view = 'group' and basis = 'balance' and elimination_kind = 'matched'
),

{# accounts whose difference legs would mix into the cumulative amounts #}
difference_accounts as (
    select distinct consolidation_group, debit_account as account
    from {{ ref('gold_ic_eliminations') }} where elimination_kind = 'difference'
    union distinct
    select distinct consolidation_group, credit_account as account
    from {{ ref('gold_ic_eliminations') }} where elimination_kind = 'difference'
),

sides as (
    select distinct consolidation_group, entity, partner, account
    from leg_sides
    where (consolidation_group, account) not in (select consolidation_group, account from difference_accounts)
),

slices as (
    select s.consolidation_group as consolidation_group, s.fiscal_year * 100 + s.fiscal_period as pk,
           s.entity as entity, s.partner as partner, s.account as account,
           {{ dim_select('s.', trailing=true) }}
           toFloat64(s.mov_group) as mov
    from {{ ref('gold_ic_side_slices') }} as s
    inner join sides as d
        on d.consolidation_group = s.consolidation_group and d.entity = s.entity
        and d.partner = s.partner and d.account = s.account
),

{# every period in which the side or its leg changes #}
grid as (
    select distinct consolidation_group, entity, partner, account, pk from (
        select consolidation_group, entity, partner, account, pk from slices
        union all
        select l.consolidation_group, l.entity, l.partner, l.account, l.pk
        from leg_sides as l
        inner join sides as d
            on d.consolidation_group = l.consolidation_group and d.entity = l.entity
            and d.partner = l.partner and d.account = l.account
    )
),

leg_to_date as (
    select g.consolidation_group as consolidation_group, g.entity as entity, g.partner as partner,
           g.account as account, g.pk as pk, sum(if(l.pk <= g.pk, l.leg, 0)) as leg_td
    from grid as g
    inner join leg_sides as l
        on l.consolidation_group = g.consolidation_group and l.entity = g.entity
        and l.partner = g.partner and l.account = g.account
    group by g.consolidation_group, g.entity, g.partner, g.account, g.pk
),

slice_to_date as (
    select g.consolidation_group as consolidation_group, g.entity as entity, g.partner as partner,
           g.account as account, g.pk as pk,
           {{ dim_select('s.', trailing=true) }}
           sum(s.mov) as bal_td
    from grid as g
    inner join slices as s
        on s.consolidation_group = g.consolidation_group and s.entity = g.entity
        and s.partner = g.partner and s.account = g.account
    where s.pk <= g.pk
    group by g.consolidation_group, g.entity, g.partner, g.account, g.pk
             {{ dim_group_by('s.', leading=true) }}
),

side_to_date as (
    select consolidation_group, entity, partner, account, pk, sum(bal_td) as side_td
    from slice_to_date
    group by consolidation_group, entity, partner, account, pk
),

aligned as (
    select t.consolidation_group as consolidation_group, t.entity as entity, t.partner as partner,
           t.account as account, t.pk as pk,
           {{ dim_select('t.', trailing=true) }}
           greatest(t.bal_td * if(sd.side_td >= 0, 1, -1), 0) as aligned_s
    from slice_to_date as t
    inner join side_to_date as sd
        on sd.consolidation_group = t.consolidation_group and sd.entity = t.entity
        and sd.partner = t.partner and sd.account = t.account and sd.pk = t.pk
),

gross as (
    select consolidation_group, entity, partner, account, pk, sum(aligned_s) as aligned_gross
    from aligned
    group by consolidation_group, entity, partner, account, pk
),

{# join_use_nulls=0: a side with no slice rows gets aligned_gross 0, which is
   exactly "cannot be split" #}
coverage as (
    select l.consolidation_group as consolidation_group, l.entity as entity, l.partner as partner,
           l.account as account, l.pk as pk, l.leg_td as leg_td, g.aligned_gross as aligned_gross,
           toUInt8(g.aligned_gross > 0 and {{ ic_leg_covered('g.aligned_gross', 'l.leg_td', 'u.minor_unit', 'u.has_minor_unit') }}) as split
    from leg_to_date as l
    left join gross as g
        on g.consolidation_group = l.consolidation_group and g.entity = l.entity
        and g.partner = l.partner and g.account = l.account and g.pk = l.pk
    {# a group with no minor unit: has_minor_unit 0, not split, as in the model;
       assert_ic_group_currency_has_minor_unit refuses it #}
    left join {{ group_minor_units() }} as u on u.consolidation_group = l.consolidation_group
),

expected as (
    select a.consolidation_group as consolidation_group, a.account as account, a.pk as pk,
           {{ dim_select('a.', trailing=true) }}
           if(c.split = 1, c.leg_td * a.aligned_s / c.aligned_gross, 0) as amount
    from aligned as a
    inner join coverage as c
        on c.consolidation_group = a.consolidation_group and c.entity = a.entity
        and c.partner = a.partner and c.account = a.account and c.pk = a.pk
    union all
    select consolidation_group, account, pk,
           {{ dim_empty_strings(trailing=true) }}
           if(split = 1, 0, leg_td) as amount
    from coverage
),

check_points as (
    select distinct consolidation_group, account, pk from expected
),

actual as (
    select cp.consolidation_group as consolidation_group, cp.account as account, cp.pk as pk,
           {{ dim_select('f.', trailing=true) }}
           -sum(f.amount) as amount
    from check_points as cp
    inner join {{ ref('gold_fully_consolidated_tb') }} as f
        on f.consolidation_group = cp.consolidation_group and f.main_account = cp.account
    where f.adjustment_type = 'ic_elimination'
      and f.fiscal_year * 100 + f.fiscal_period <= cp.pk
    group by cp.consolidation_group, cp.account, cp.pk
             {{ dim_group_by('f.', leading=true) }}
)

select
    consolidation_group,
    intDiv(pk, 100) as fiscal_year,
    pk % 100 as fiscal_period,
    account,
    {{ dim_select(trailing=true) }}
    sum(amount) as expected_minus_emitted_to_date
from (
    select * from expected
    union all
    select * from actual
)
group by consolidation_group, pk, account {{ dim_group_by(leading=true) }}
having abs(sum(amount)) > {{ floor }}
