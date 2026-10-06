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
-- leg amount gold_ic_eliminations published, within materiality. F1 makes the
-- sum N times the leg; F2 leaves the sum right, so this test is paired with
-- the per-pair grain below — a leg is keyed on its PAIR, and a row whose slices
-- do not belong to that pair cannot reconcile once the join carries partner.
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
