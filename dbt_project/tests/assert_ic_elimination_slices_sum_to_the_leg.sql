-- konsolidat#245 option C. PR #260 review finding F4: nothing tested what
-- layer 2 actually does. The old test asserted sum(slice_mov) = side_mov per
-- side, which the window function produces and so cannot fail arithmetically.
-- The two things that CAN go wrong were untested, and both were real:
--
--   F1  a side whose slices summed to zero took factor 1.0 on EVERY slice, so
--       the leg was emitted N times at full amount;
--   F2  the apportionment denominator omitted the partner, so a leg was split
--       over balances owed to other partners — totals right, slices wrong.
--
-- Totals and "nets to zero" cannot see F2 at all. This asserts the thing that
-- can: for each elimination leg, layer 2's per-slice amounts must sum to the
-- leg amount gold_ic_eliminations published, within materiality.
--
-- WHAT THIS TEST IS AND IS NOT, corrected after the re-review said so.
--
-- It CANNOT FAIL on the current code. Shares are normalised in all three
-- branches (apportionable sums to 1, flat is one row at 1.0, a join miss is
-- one row at 1.0), so sum(emitted) = leg for every possible input. It is a
-- REGRESSION GUARD — it would have caught the original defect, where a side
-- whose slices cancelled emitted the leg N times at full amount — and it is
-- NOT evidence that layer 2 is right today.
--
-- It is also BLIND TO MISATTRIBUTION. An earlier version of this header
-- claimed it was "paired with the per-pair grain below"; there is no pair
-- grain below. legs_by_account groups on (group, year, period, account) only:
-- entity is dropped and partner was never carried, so a leg split across the
-- wrong partner's slices reconciles here perfectly. That defect is prevented
-- by the join carrying partner, not detected here.
--
-- And legs_by_account's netting hides one case by construction: when
-- counterpart_account is blank both legs of a pair land on one account, so a
-- symmetric error on both sides nets to zero on both sides of the comparison.
--
-- assert_ic_elimination_share_is_bounded is the REGRESSION GUARD for the
-- magnification defects. Round 4 is explicit that it, too, cannot fail on
-- correct code: shares are in [0,1] and sum to 1, so no slice can exceed its
-- leg. It goes red on the round-2 and round-3 code (and on its committed
-- .must_flag fixture), which is what it is for. No test in this layer proves
-- today's attribution is RIGHT; they prove it has not regressed.
--
-- Error severity: a leg that does not reconcile is a wrong consolidated number.
-- One row per offending leg.
with legs as (
    select
        consolidation_group,
        fiscal_year,
        fiscal_period,
        debit_entity as entity,
        debit_account as account,
        'debit' as leg,
        sum(debit_elimination) as leg_amount
    from {{ ref('gold_ic_eliminations') }}
    where elimination_view = 'group'
    group by consolidation_group, fiscal_year, fiscal_period, debit_entity, debit_account

    union all

    select
        consolidation_group,
        fiscal_year,
        fiscal_period,
        credit_entity as entity,
        credit_account as account,
        'credit' as leg,
        sum(credit_elimination) as leg_amount
    from {{ ref('gold_ic_eliminations') }}
    where elimination_view = 'group'
    group by consolidation_group, fiscal_year, fiscal_period, credit_entity, credit_account
),

{# what layer 2 emitted, summed back over the slices #}
emitted as (
    select
        consolidation_group,
        fiscal_year,
        fiscal_period,
        main_account as account,
        sum(amount) as emitted_amount
    from {{ ref('gold_fully_consolidated_tb') }}
    where adjustment_type in ('ic_elimination', 'ic_elimination_nci')
    group by consolidation_group, fiscal_year, fiscal_period, main_account
),

{# the legs that share an account net together before comparison: both legs of a
   pair can post to the same account when counterpart_account is blank #}
legs_by_account as (
    select
        consolidation_group,
        fiscal_year,
        fiscal_period,
        account,
        sum(leg_amount) as leg_amount
    from legs
    group by consolidation_group, fiscal_year, fiscal_period, account
)

select
    l.consolidation_group,
    l.fiscal_year,
    l.fiscal_period,
    l.account,
    l.leg_amount,
    e.emitted_amount,
    e.emitted_amount - l.leg_amount as difference
from legs_by_account as l
inner join emitted as e
    on l.consolidation_group = e.consolidation_group
    and l.fiscal_year = e.fiscal_year
    and l.fiscal_period = e.fiscal_period
    and l.account = e.account
where abs(e.emitted_amount - l.leg_amount) > {{ materiality_floor() }}
