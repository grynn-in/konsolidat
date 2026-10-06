-- konsolidat#245. No elimination slice may be moved further than its own leg.
--
-- THE BOUND IS 1, which is what the code guarantees: layer 2 weights by
-- abs(slice)/gross, so shares lie in [0,1] and sum to 1. The previous version
-- of this test asserted 100x while the code of the day guaranteed 50.5x, so it
-- was slack by a factor of two and could not fail on any input — the exact
-- tautology it was written to replace (re-review round 3, F2). A test whose
-- threshold trails the code does not pin the code.
--
-- KEYED ON THE PAIR, not the account (re-review round 3, F3). Keyed on account
-- alone, a small leg exploded on an account that also carries a large leg was
-- invisible to max(): one measured fixture hid a 100,000x violation on an
-- account whose other leg was 5,000,000. Real intercompany control accounts
-- carry many legs of very different sizes, so account-level max() is the wrong
-- grain.
--
-- Error severity: a slice moved further than its leg is a wrong consolidated
-- number, and every total-based check passes while it happens.
with legs as (
    select
        consolidation_group, fiscal_year, fiscal_period, rule_id,
        debit_entity as entity, credit_entity as partner, debit_account as account,
        sum(abs(debit_elimination)) as leg_size
    from {{ ref('gold_ic_eliminations') }}
    where elimination_view = 'group'
    group by consolidation_group, fiscal_year, fiscal_period, rule_id,
             debit_entity, credit_entity, debit_account

    union all

    select
        consolidation_group, fiscal_year, fiscal_period, rule_id,
        credit_entity as entity, debit_entity as partner, credit_account as account,
        sum(abs(credit_elimination)) as leg_size
    from {{ ref('gold_ic_eliminations') }}
    where elimination_view = 'group'
    group by consolidation_group, fiscal_year, fiscal_period, rule_id,
             credit_entity, debit_entity, credit_account
),

{# PER LEG, keyed on journal_id — which the emitted rows already carry
   (gold_fully_consolidated_tb emits e.rule_id as journal_id on both layer-2
   legs). Round 4 found the previous version INERT: it grouped `legs` finely
   and then summed straight back up to (group, period, account), and a sum of
   sums over a finer partition IS the sum over the coarser one, so `allowed`
   was every leg on the account added together. A 100,000x violation on a leg
   of 1 passed because the same account carried a leg of 5,000,000 — verbatim
   the case the previous commit claimed to fix. With more than ~100 legs on an
   account that bound was looser than the 100x-of-max it replaced.

   The reason given for the loose bound was also false: it claimed layer 2 sums
   several legs into one emitted row. It does not — `ic_elims` has no GROUP BY,
   so each gold_ic_eliminations row produces its own output rows. There is
   nothing to false-fire, so the strict per-leg bound is the right one. #}
leg_bound as (
    select
        consolidation_group, fiscal_year, fiscal_period, account, rule_id,
        sum(leg_size) as allowed
    from legs
    group by consolidation_group, fiscal_year, fiscal_period, account, rule_id
),

emitted as (
    select
        consolidation_group, fiscal_year, fiscal_period, main_account as account,
        journal_id as rule_id,
        max(abs(amount)) as biggest_slice
    from {{ ref('gold_fully_consolidated_tb') }}
    where adjustment_type in ('ic_elimination', 'ic_elimination_nci')
    group by consolidation_group, fiscal_year, fiscal_period, main_account, journal_id
)

select
    e.consolidation_group,
    e.fiscal_year,
    e.fiscal_period,
    e.account,
    e.rule_id,
    b.allowed,
    e.biggest_slice,
    e.biggest_slice / nullIf(b.allowed, 0) as times_the_leg
from emitted as e
inner join leg_bound as b
    on b.consolidation_group = e.consolidation_group
    and b.fiscal_year = e.fiscal_year
    and b.fiscal_period = e.fiscal_period
    and b.account = e.account
    and b.rule_id = e.rule_id
{# a cent of slack for Float64 summation, not a tolerance on the bound #}
where e.biggest_slice > b.allowed + {{ materiality_floor() }}
