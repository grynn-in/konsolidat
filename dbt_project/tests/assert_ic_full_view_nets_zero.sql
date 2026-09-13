{#
    #175 re-review H1: the full (100%) view nets each pair to zero.

    The consolidation report's Consolidated column is the group view
    (gold_fully_consolidated_tb) plus the NCI view (nci_amount per account,
    plus the NCI view's eliminations). With A 100% and B 80% on 1000/-1000,
    the group view eliminated -1000 and +800 and put +200 on the NCI line, but
    nothing eliminated B's minority share (-200) of the payable, so the
    payable showed -200 at 100%.

    Per pair and row, on the pair's basis (decision 14): what both sides hold
    at 100% (balance_a + balance_b = group_amount + nci_amount) plus every
    elimination on the pair's own sides, group and NCI view, nets to zero when
    the group has an intercompany-difference account, and to the 100%
    residuals when it has none. The NCI line and the difference account are
    destinations, not the pair's sides.

    The group view on its own is assert_ic_elimination_nets_zero.
#}

with pair_legs as (
    select
        consolidation_group, fiscal_year, fiscal_period, entity_a, account_a, entity_b, account_b,
        sum(
            if((debit_account = account_a and debit_entity = entity_a)
               or (debit_account = account_b and debit_entity = entity_b), debit_elimination, 0)
            + if((credit_account = account_a and credit_entity = entity_a)
                 or (credit_account = account_b and credit_entity = entity_b), credit_elimination, 0)
        ) as legs_in_period
    from {{ ref('gold_ic_eliminations') }}
    where rule_type = 'balance'
    group by consolidation_group, fiscal_year, fiscal_period, entity_a, account_a, entity_b, account_b
),

pair_rows as (
    select
        r.consolidation_group as consolidation_group, r.fiscal_year as fiscal_year,
        r.fiscal_period as fiscal_period, r.entity_a as entity_a, r.account_a as account_a,
        r.entity_b as entity_b, r.account_b as account_b, r.basis as basis,
        r.balance_a + r.balance_b as held_at_100,
        if(r.ic_difference_account != '', 0, r.residual_a + r.residual_b) as should_remain,
        {# join_use_nulls=0: a period with no legs adds 0, which is right #}
        pl.legs_in_period as legs_in_period
    from {{ ref('gold_ic_reconciliation') }} as r
    left join pair_legs as pl
        on pl.consolidation_group = r.consolidation_group and pl.fiscal_year = r.fiscal_year
        and pl.fiscal_period = r.fiscal_period and pl.entity_a = r.entity_a
        and pl.account_a = r.account_a and pl.entity_b = r.entity_b and pl.account_b = r.account_b
),

pair_to_date as (
    select
        *,
        sum(legs_in_period) over (
            partition by consolidation_group, entity_a, account_a, entity_b, account_b
            order by fiscal_year, fiscal_period rows between unbounded preceding and current row
        ) as legs_to_date
    from pair_rows
)

select
    consolidation_group,
    fiscal_year,
    fiscal_period,
    concat(entity_a, '/', account_a, ' <> ', entity_b, '/', account_b) as detail,
    held_at_100 + if(basis = 'balance', legs_to_date, legs_in_period) - should_remain as net
from pair_to_date
where abs(held_at_100 + if(basis = 'balance', legs_to_date, legs_in_period) - should_remain) > 0.01
