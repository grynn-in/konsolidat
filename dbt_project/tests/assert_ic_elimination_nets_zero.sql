{#
    Intercompany elimination nets to zero, three ways (konsolidat#148).

    Every elimination row carries both legs, so "debit + credit = 0" per row is
    true by construction and proves little on its own. The checks that can fail:

    1. entry: each row's two legs net to zero (kept: it is what the layer
       relies on);
    2. layer: the ic_elimination layer of gold_fully_consolidated_tb nets to
       zero per group and period, so both legs of every entry (the NCI line's
       included, decision 12) reached it;
    3. pair: on the pair's basis (decision 14: to date for a balance-sheet
       pair, the period for a P&L pair), what the GROUP VIEW holds of the two
       sides plus its eliminations nets to zero (the 100% view is
       assert_ic_full_view_nets_zero) when the group has an
       intercompany-difference account, and to exactly the group share of
       the residuals when it has none (only the matched amount is eliminated
       then).
#}

with eliminations as (
    select * from {{ ref('gold_ic_eliminations') }}
),

entry_check as (
    select
        'entry' as failed_check,
        consolidation_group,
        fiscal_year,
        fiscal_period,
        rule_id as detail,
        debit_elimination + credit_elimination as net
    from eliminations
    where abs(debit_elimination + credit_elimination) > 0.01
),

layer_check as (
    select
        'layer' as failed_check,
        consolidation_group,
        fiscal_year,
        fiscal_period,
        '' as detail,
        sum(amount) as net
    from {{ ref('gold_fully_consolidated_tb') }}
    where adjustment_type in ('ic_elimination', 'ic_elimination_nci')
    group by consolidation_group, fiscal_year, fiscal_period
    having abs(sum(amount)) > 0.01
),

{# the legs on the pair's own sides: its accounts, at its entities. Not the
   difference account, not the NCI line. #}
pair_legs as (
    select
        consolidation_group, fiscal_year, fiscal_period, entity_a, account_a, entity_b, account_b,
        sum(
            if((debit_account = account_a and debit_entity = entity_a)
               or (debit_account = account_b and debit_entity = entity_b), debit_elimination, 0)
            + if((credit_account = account_a and credit_entity = entity_a)
                 or (credit_account = account_b and credit_entity = entity_b), credit_elimination, 0)
        ) as legs_in_period
    from eliminations
    where rule_type = 'balance' and elimination_view = 'group'
    group by consolidation_group, fiscal_year, fiscal_period, entity_a, account_a, entity_b, account_b
),

pair_rows as (
    select
        r.consolidation_group as consolidation_group, r.fiscal_year as fiscal_year,
        r.fiscal_period as fiscal_period, r.entity_a as entity_a, r.account_a as account_a,
        r.entity_b as entity_b, r.account_b as account_b, r.basis as basis,
        r.group_balance_a + r.group_balance_b as held,
        if(r.ic_difference_account != '', 0, r.residual_a * r.share_a + r.residual_b * r.share_b) as should_remain,
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
),

pair_check as (
    select
        'pair' as failed_check,
        consolidation_group,
        fiscal_year,
        fiscal_period,
        concat(entity_a, '/', account_a, ' <> ', entity_b, '/', account_b) as detail,
        held + if(basis = 'balance', legs_to_date, legs_in_period) - should_remain as net
    from pair_to_date
    where abs(held + if(basis = 'balance', legs_to_date, legs_in_period) - should_remain) > 0.01
)

select * from entry_check
union all
select * from layer_check
union all
select * from pair_check
