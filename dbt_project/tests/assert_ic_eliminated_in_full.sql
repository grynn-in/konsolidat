{#
    konsol#117 pair 2 K3 (konsolidat#204 option (a); Deepak Pai, 8 Nov 2026):
    intercompany eliminations are posted IN FULL.

    IFRS 10.B86(c): intragroup assets and liabilities, equity, income,
    expenses and cash flows are eliminated in full. Layer 1 carries a full
    method subsidiary at 100%, so the matched amount of each side is
    eliminated at 100% whatever the group's holding in it; the minority's
    share is one NCI line (gold_nci_movement_schedule), not a part of the
    elimination. This supersedes decision 12 (13 Sep 2026), which eliminated
    at the share both sides hold and sent the rest to an NCI leg.

    Per (group, period, pair), the 'matched' legs on each side's own account
    and entity, on the pair's basis (decision 14: to date for a balance-sheet
    pair, in the period for a P&L pair), equal minus the matched amount in
    the direction of that side's balance, full_a = -sign(balance_a) * matched
    and full_b likewise (gold_ic_reconciliation). A share other than 100%
    leaves a side eliminated by less.
#}

with eliminations as (
    select * from {{ ref('gold_ic_eliminations') }}
    where rule_type = 'balance' and elimination_kind = 'matched'
),

side_legs as (
    select
        consolidation_group, fiscal_year, fiscal_period, entity_a, account_a, entity_b, account_b,
        sum(
            if(debit_account = account_a and debit_entity = entity_a, debit_elimination, 0)
            + if(credit_account = account_a and credit_entity = entity_a, credit_elimination, 0)
        ) as legs_a,
        sum(
            if(debit_account = account_b and debit_entity = entity_b, debit_elimination, 0)
            + if(credit_account = account_b and credit_entity = entity_b, credit_elimination, 0)
        ) as legs_b
    from eliminations
    group by consolidation_group, fiscal_year, fiscal_period, entity_a, account_a, entity_b, account_b
),

pair_rows as (
    select
        r.consolidation_group as consolidation_group, r.fiscal_year as fiscal_year,
        r.fiscal_period as fiscal_period, r.entity_a as entity_a, r.account_a as account_a,
        r.entity_b as entity_b, r.account_b as account_b, r.basis as basis,
        -sign(r.balance_a) * r.matched_amount as full_a,
        -sign(r.balance_b) * r.matched_amount as full_b,
        {# join_use_nulls=0: a period with no matched leg adds 0, which is right #}
        sl.legs_a as legs_a,
        sl.legs_b as legs_b
    from {{ ref('gold_ic_reconciliation') }} as r
    left join side_legs as sl
        on sl.consolidation_group = r.consolidation_group and sl.fiscal_year = r.fiscal_year
        and sl.fiscal_period = r.fiscal_period and sl.entity_a = r.entity_a
        and sl.account_a = r.account_a and sl.entity_b = r.entity_b and sl.account_b = r.account_b
),

pair_to_date as (
    select
        *,
        sum(legs_a) over w as legs_a_to_date,
        sum(legs_b) over w as legs_b_to_date
    from pair_rows
    window w as (
        partition by consolidation_group, entity_a, account_a, entity_b, account_b
        order by fiscal_year, fiscal_period rows between unbounded preceding and current row
    )
)

select
    consolidation_group,
    fiscal_year,
    fiscal_period,
    concat(entity_a, '/', account_a, ' <> ', entity_b, '/', account_b) as pair,
    full_a,
    if(basis = 'balance', legs_a_to_date, legs_a) as eliminated_a,
    full_b,
    if(basis = 'balance', legs_b_to_date, legs_b) as eliminated_b
from pair_to_date
where abs(full_a - if(basis = 'balance', legs_a_to_date, legs_a)) > 0.01
   or abs(full_b - if(basis = 'balance', legs_b_to_date, legs_b)) > 0.01
