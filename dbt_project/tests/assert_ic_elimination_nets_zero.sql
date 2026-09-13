{#
    Intercompany elimination nets to zero, three ways (konsolidat#148).

    Every elimination row carries both legs, so "debit + credit = 0" per row is
    true by construction and proves little on its own. The checks that can fail:

    1. entry: each row's two legs net to zero (kept: it is what the layer
       relies on);
    2. layer: the ic_elimination layer of gold_fully_consolidated_tb nets to
       zero per group and period, so both legs of every entry reached it;
    3. pair: after its eliminations, each intercompany pair's balances net to
       zero when the group has an intercompany-difference account, and to
       exactly the pair's difference when it has none (only the matched
       amount is eliminated then).
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
    where adjustment_type = 'ic_elimination'
    group by consolidation_group, fiscal_year, fiscal_period
    having abs(sum(amount)) > 0.01
),

pair_amounts as (
    {# the pair's balances, less what should remain of them #}
    select
        consolidation_group, fiscal_year, fiscal_period, entity_a, account_a, entity_b, account_b,
        balance_a + balance_b - if(ic_difference_account != '', 0, difference) as amount
    from {{ ref('gold_ic_reconciliation') }}

    union all

    {# plus its legs on the intercompany accounts (not the difference account) #}
    select
        consolidation_group, fiscal_year, fiscal_period, entity_a, account_a, entity_b, account_b,
        {# not `x in (col, col)`: 24.8 wants a constant right-hand side there too #}
        if(debit_account = account_a or debit_account = account_b, debit_elimination, 0)
            + if(credit_account = account_a or credit_account = account_b, credit_elimination, 0)
    from eliminations
    where rule_type = 'balance'
),

pair_check as (
    select
        'pair' as failed_check,
        consolidation_group,
        fiscal_year,
        fiscal_period,
        concat(entity_a, '/', account_a, ' <> ', entity_b, '/', account_b) as detail,
        sum(amount) as net
    from pair_amounts
    group by consolidation_group, fiscal_year, fiscal_period, entity_a, account_a, entity_b, account_b
    having abs(sum(amount)) > 0.01
)

select * from entry_check
union all
select * from layer_check
union all
select * from pair_check
