-- konsolidat#395 (PR #404 review): a fully matched balance-sheet intercompany side leaves
-- nothing on any of its slices.
--
-- This test does not use ic_leg_covered() or any other part of the coverage decision. It reads
-- what the model emitted and checks a consequence of eliminating in full (konsol#117 pair 2 K3,
-- IFRS 10.B86(c)): when a side's matched elimination to date is exactly minus its balance to date,
-- and no slice holds a balance opposite to the side's net, every slice is eliminated to exactly its
-- own balance. Each slice gets L(t) x aligned_s / aligned_gross with aligned_gross = |side| = |L(t)|,
-- so its consolidated intercompany balance to date (its own balance plus the ic_elimination rows on
-- it) is 0. A side sent whole to the blank slice instead leaves its balance on its own slices and
-- the opposite amount on the blank slice: two rows here.
--
-- The model and assert_ic_slice_to_date_eliminated decide coverage through the same macro, so a
-- defect in that shared decision is invisible to that test. This one compares the model's output
-- with the input balances only.
--
-- Checked per (group, account, period to date), on accounts where:
--   * every elimination leg is a balance-basis MATCHED leg (no difference leg, which sits on the
--     blank slice by konsolidat#245 Q1 A, and no movement-basis leg);
--   * every side on the account is fully matched to date: |L(t) + side balance| <= the floor
--     (the residual of a side, which translated legs leave at a sub-cent size);
--   * no slice of any side on the account opposes its side's net to date by more than the floor
--     (decision 2B gives such a slice nothing, so it keeps its balance).
-- The slice balance is gold_ic_side_slices (partner set), so a third-party balance on the same
-- account does not enter.
--
-- Tolerance: the account's total to date may differ from 0 by the floor plus the residuals already
-- accepted on its sides, floor + sum of |L(t) + side balance| over the sides on the account. Each
-- side was accepted within the floor, so several sides on one account can add past the floor with
-- nothing wrong (28 Nov 2026, aquila-bike example: 15 false rows of 0.005 to 0.012). This cannot hide
-- a leg sent whole to the blank slice: that leaves an amount of the leg's size on the slice and the
-- opposite on the blank slice, each far over a tolerance made of sub-floor residuals (every side
-- counted is within the floor of its leg, so the tolerance is the floor times at most the number of
-- sides plus one, and a leg is many times the floor).
--
-- Error severity: a slice keeping an intercompany balance the group eliminated in full is a wrong
-- consolidated number that the account total does not show.
{% set floor = materiality_floor() %}

with legs as (
    select consolidation_group, fiscal_year * 100 + fiscal_period as pk,
           debit_entity as entity, credit_entity as partner, debit_account as account,
           toFloat64(debit_elimination) as leg
    from {{ ref('gold_ic_eliminations') }}
    where basis = 'balance' and elimination_kind = 'matched'
    union all
    select consolidation_group, fiscal_year * 100 + fiscal_period as pk,
           credit_entity as entity, debit_entity as partner, credit_account as account,
           toFloat64(credit_elimination) as leg
    from {{ ref('gold_ic_eliminations') }}
    where basis = 'balance' and elimination_kind = 'matched'
),

{# accounts carrying any other leg: a difference leg or a movement-basis leg #}
other_accounts as (
    select distinct consolidation_group, debit_account as account
    from {{ ref('gold_ic_eliminations') }}
    where not (basis = 'balance' and elimination_kind = 'matched')
    union distinct
    select distinct consolidation_group, credit_account as account
    from {{ ref('gold_ic_eliminations') }}
    where not (basis = 'balance' and elimination_kind = 'matched')
),

sides as (
    select distinct consolidation_group, entity, partner, account
    from legs
    where (consolidation_group, account) not in (select consolidation_group, account from other_accounts)
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

{# every period in which anything on the account changes, for every side on it #}
account_points as (
    select distinct consolidation_group, account, pk from (
        select consolidation_group, account, pk from slices
        union all
        select l.consolidation_group, l.account, l.pk
        from legs as l
        inner join sides as d
            on d.consolidation_group = l.consolidation_group and d.entity = l.entity
            and d.partner = l.partner and d.account = l.account
    )
),

side_points as (
    select p.consolidation_group as consolidation_group, d.entity as entity, d.partner as partner,
           p.account as account, p.pk as pk
    from account_points as p
    inner join sides as d
        on d.consolidation_group = p.consolidation_group and d.account = p.account
),

leg_to_date as (
    select p.consolidation_group as consolidation_group, p.entity as entity, p.partner as partner,
           p.account as account, p.pk as pk, sum(if(l.pk <= p.pk, l.leg, 0)) as leg_td
    from side_points as p
    inner join legs as l
        on l.consolidation_group = p.consolidation_group and l.entity = p.entity
        and l.partner = p.partner and l.account = p.account
    group by p.consolidation_group, p.entity, p.partner, p.account, p.pk
),

slice_to_date as (
    select p.consolidation_group as consolidation_group, p.entity as entity, p.partner as partner,
           p.account as account, p.pk as pk,
           {{ dim_select('s.', trailing=true) }}
           sum(s.mov) as bal_td
    from side_points as p
    inner join slices as s
        on s.consolidation_group = p.consolidation_group and s.entity = p.entity
        and s.partner = p.partner and s.account = p.account
    where s.pk <= p.pk
    group by p.consolidation_group, p.entity, p.partner, p.account, p.pk
             {{ dim_group_by('s.', leading=true) }}
),

side_to_date as (
    select consolidation_group, entity, partner, account, pk, sum(bal_td) as side_td
    from slice_to_date
    group by consolidation_group, entity, partner, account, pk
),

{# leg plus balance per side, as a UNION ALL + GROUP BY: a side with no slice row to date
   has only its leg here, which is "not fully matched" unless the leg is 0 #}
side_residual as (
    select consolidation_group, entity, partner, account, pk, sum(amount) as residual
    from (
        select consolidation_group, entity, partner, account, pk, leg_td as amount from leg_to_date
        union all
        select consolidation_group, entity, partner, account, pk, side_td as amount from side_to_date
    )
    group by consolidation_group, entity, partner, account, pk
),

excluded as (
    select distinct consolidation_group, account, pk
    from side_residual
    where abs(residual) > {{ floor }}
    union distinct
    select distinct t.consolidation_group, t.account, t.pk
    from slice_to_date as t
    inner join side_to_date as sd
        on sd.consolidation_group = t.consolidation_group and sd.entity = t.entity
        and sd.partner = t.partner and sd.account = t.account and sd.pk = t.pk
    where t.bal_td * if(sd.side_td >= 0, 1, -1) < -{{ floor }}
),

{# the residuals accepted on each checked account and period, as a tolerance #}
accepted_residual as (
    select consolidation_group, account, pk, sum(abs(residual)) as tolerance
    from side_residual
    group by consolidation_group, account, pk
),

check_points as (
    select distinct consolidation_group, account, pk
    from account_points
    where (consolidation_group, account, pk) not in (select consolidation_group, account, pk from excluded)
),

balances as (
    select c.consolidation_group as consolidation_group, c.account as account, c.pk as pk,
           {{ dim_select('t.', trailing=true) }}
           t.bal_td as amount
    from check_points as c
    inner join slice_to_date as t
        on t.consolidation_group = c.consolidation_group and t.account = c.account and t.pk = c.pk
),

eliminated as (
    select c.consolidation_group as consolidation_group, c.account as account, c.pk as pk,
           {{ dim_select('f.', trailing=true) }}
           sum(f.amount) as amount
    from check_points as c
    inner join {{ ref('gold_fully_consolidated_tb') }} as f
        on f.consolidation_group = c.consolidation_group and f.main_account = c.account
    where f.adjustment_type = 'ic_elimination'
      and f.fiscal_year * 100 + f.fiscal_period <= c.pk
    group by c.consolidation_group, c.account, c.pk
             {{ dim_group_by('f.', leading=true) }}
)

select
    t.consolidation_group as consolidation_group,
    intDiv(t.pk, 100) as fiscal_year,
    t.pk % 100 as fiscal_period,
    t.account as account,
    {{ dim_select('t.', trailing=true) }}
    t.consolidated_ic_to_date as consolidated_ic_to_date
from (
    select consolidation_group, pk, account,
           {{ dim_select(trailing=true) }}
           sum(amount) as consolidated_ic_to_date
    from (
        select * from balances
        union all
        select * from eliminated
    )
    group by consolidation_group, pk, account {{ dim_group_by(leading=true) }}
) as t
inner join accepted_residual as r
    on r.consolidation_group = t.consolidation_group and r.account = t.account and r.pk = t.pk
where abs(t.consolidated_ic_to_date) > {{ floor }} + r.tolerance
