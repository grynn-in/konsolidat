{#
    Decision 14 (13 Sep 2026): a balance-sheet intercompany pair matches on its
    balance to date (from inception, as gold_balance_sheet carries it). A P&L
    pair matches on the period's movement.

    1. basis: a pair on a balance-sheet account is on the 'balance' basis, one
       on a P&L account on 'movement' (is_balance_sheet of account_a in
       gold_consolidated_trial_balance).
    2. value: each side equals its 100% amount recomputed from
       gold_consolidated_trial_balance on that basis (ic_expected_pair_values).
       A balance-sheet pair booked in different periods is compared on what
       has been booked to date, so it matches once both sides are in.
#}

with expected as (
    {{ ic_expected_pair_values() }}
),

account_basis as (
    select main_account as basis_account, max(is_balance_sheet) as is_bs
    from {{ ref('gold_consolidated_trial_balance') }}
    group by main_account
),

basis_check as (
    select
        'basis' as failed_check,
        r.consolidation_group as consolidation_group,
        r.fiscal_year as fiscal_year,
        r.fiscal_period as fiscal_period,
        concat(r.entity_a, '/', r.account_a, ' <> ', r.entity_b, '/', r.account_b, ': ', r.basis) as detail,
        toFloat64(ab.is_bs) as got,
        toFloat64(0) as expected
    from {{ ref('gold_ic_reconciliation') }} as r
    inner join account_basis as ab on ab.basis_account = r.account_a
    where r.basis != if(ab.is_bs = 1, 'balance', 'movement')
),

value_check as (
    select
        'value' as failed_check,
        r.consolidation_group,
        r.fiscal_year,
        r.fiscal_period,
        concat(r.entity_a, '/', r.account_a, ' <> ', r.entity_b, '/', r.account_b) as detail,
        r.balance_a + r.balance_b as got,
        e.expected_a + e.expected_b as expected
    from {{ ref('gold_ic_reconciliation') }} as r
    left join expected as e
        on e.consolidation_group = r.consolidation_group and e.fiscal_year = r.fiscal_year
        and e.fiscal_period = r.fiscal_period and e.entity_a = r.entity_a and e.account_a = r.account_a
        and e.entity_b = r.entity_b and e.account_b = r.account_b
    where abs(r.balance_a - e.expected_a) > 0.01
       or abs(r.balance_b - e.expected_b) > 0.01
)

select * from basis_check
union all
select * from value_check
