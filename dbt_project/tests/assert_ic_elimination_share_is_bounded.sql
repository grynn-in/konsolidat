-- konsolidat#245, PR #260 re-review finding 1. The test that CAN fail.
--
-- The two assertions this layer already had cannot fail on any input: shares
-- are normalised by construction, so "the slices sum to the leg" and "the
-- slices sum to the side" are both tautologies. They are regression guards,
-- not evidence. What was missing is a bound on how far a single slice can be
-- moved, which is the failure the near-zero side actually produces:
--
--   slices +1000.00 and -999.99  ->  side nets to 0.01
--   a -1000 leg                  ->  -100,000,000.0001 and +99,999,000.0001
--
-- Those sum to -1000, so every total, every "nets to zero" check and both
-- existing assertions pass while two cost-centre lines carry +/-1e8.
--
-- divisible_share() bounds it: a side is apportioned only when its net is at
-- least that fraction of its gross, so no slice can take a share larger than
-- 1 / divisible_share(). This asserts the consequence directly, against
-- gold_ic_eliminations' published legs, and it is the only test here that
-- fails when the guard is wrong.
--
-- One row per elimination row that exceeds the bound. Error severity: an
-- amount two orders of magnitude out is a wrong consolidated number, however
-- well it sums.
{% set bound = 1.0 / divisible_share() | float %}

with legs as (
    select
        consolidation_group,
        fiscal_year,
        fiscal_period,
        debit_account as account,
        max(abs(debit_elimination)) as leg_size
    from {{ ref('gold_ic_eliminations') }}
    where elimination_view = 'group'
    group by consolidation_group, fiscal_year, fiscal_period, debit_account

    union all

    select
        consolidation_group,
        fiscal_year,
        fiscal_period,
        credit_account as account,
        max(abs(credit_elimination)) as leg_size
    from {{ ref('gold_ic_eliminations') }}
    where elimination_view = 'group'
    group by consolidation_group, fiscal_year, fiscal_period, credit_account
),

leg_size_by_account as (
    select
        consolidation_group, fiscal_year, fiscal_period, account,
        max(leg_size) as leg_size
    from legs
    group by consolidation_group, fiscal_year, fiscal_period, account
),

emitted as (
    select
        consolidation_group,
        fiscal_year,
        fiscal_period,
        main_account as account,
        max(abs(amount)) as biggest_slice
    from {{ ref('gold_fully_consolidated_tb') }}
    where adjustment_type in ('ic_elimination', 'ic_elimination_nci')
    group by consolidation_group, fiscal_year, fiscal_period, main_account
)

select
    e.consolidation_group,
    e.fiscal_year,
    e.fiscal_period,
    e.account,
    l.leg_size,
    e.biggest_slice,
    e.biggest_slice / nullIf(l.leg_size, 0) as times_the_leg
from emitted as e
inner join leg_size_by_account as l
    on l.consolidation_group = e.consolidation_group
    and l.fiscal_year = e.fiscal_year
    and l.fiscal_period = e.fiscal_period
    and l.account = e.account
where l.leg_size > {{ materiality_floor() }}
  and e.biggest_slice > l.leg_size * {{ bound }}
