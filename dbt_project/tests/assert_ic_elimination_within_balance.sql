{#
    konsolidat#148 / konsol#159 (decision 1, 13 Sep 2026): elimination never
    exceeds the balance it cancels.

    The engine this replaced joined every ordered entity pair and eliminated
    2.61M against a 2.56M intercompany revenue balance, and 31.5M against a
    14.5M payables balance. This is the invariant that would have caught both.

    Two checks, balance eliminations only (unrealized profit is a margin on
    inventory, not a balance being cancelled):

    1. account: per (group, period, account), total elimination does not exceed
       the account's consolidated balance. The balance is taken gross, as the
       sum of |balance| per (entity, partner): a partnerless row or an entity
       with the opposite sign stays on the account after elimination, and a
       net figure would flag a correct elimination of the rest. Legs on the
       group's intercompany-difference account are its destination, not an
       elimination of its balance, so they are left out.
    2. side: per pair, each side is eliminated by no more than its own balance,
       and in the direction that reduces it.
#}

with eliminations as (
    select * from {{ ref('gold_ic_eliminations') }}
    where rule_type = 'balance'
),

legs as (
    select consolidation_group, fiscal_year, fiscal_period,
           entity_a, account_a, entity_b, account_b,
           debit_entity as leg_entity, debit_account as leg_account, debit_elimination as amount
    from eliminations
    union all
    select consolidation_group, fiscal_year, fiscal_period,
           entity_a, account_a, entity_b, account_b,
           credit_entity, credit_account, credit_elimination
    from eliminations
),

difference_accounts as (
    select distinct consolidation_group, ic_difference_account
    from {{ ref('gold_ic_reconciliation') }}
    where ic_difference_account != ''
),

per_account as (
    select consolidation_group, fiscal_year, fiscal_period, leg_account as main_account,
           amount as eliminated, toFloat64(0) as gross_balance
    from legs
    where (consolidation_group, leg_account) not in (select consolidation_group, ic_difference_account from difference_accounts)

    union all

    select consolidation_group, fiscal_year, fiscal_period, main_account,
           toFloat64(0), abs(slice_balance)
    from (
        select consolidation_group, fiscal_year, fiscal_period, main_account,
               data_area_id, partner_data_area_id, sum(group_amount) as slice_balance
        from {{ ref('gold_consolidated_trial_balance') }}
        group by consolidation_group, fiscal_year, fiscal_period, main_account,
                 data_area_id, partner_data_area_id
    )
),

account_check as (
    select
        'account' as failed_check,
        consolidation_group,
        fiscal_year,
        fiscal_period,
        main_account as detail,
        sum(eliminated) as total_eliminated,
        sum(gross_balance) as consolidated_balance
    from per_account
    group by consolidation_group, fiscal_year, fiscal_period, main_account
    having abs(total_eliminated) > consolidated_balance + 0.01
),

per_side as (
    select
        consolidation_group, fiscal_year, fiscal_period, entity_a, account_a, entity_b, account_b,
        sumIf(amount, leg_entity = entity_a and leg_account = account_a) as eliminated_a,
        sumIf(amount, leg_entity = entity_b and leg_account = account_b) as eliminated_b
    from legs
    group by consolidation_group, fiscal_year, fiscal_period, entity_a, account_a, entity_b, account_b
),

side_check as (
    select
        'side' as failed_check,
        s.consolidation_group as consolidation_group,
        s.fiscal_year as fiscal_year,
        s.fiscal_period as fiscal_period,
        concat(s.entity_a, '/', s.account_a, ' <> ', s.entity_b, '/', s.account_b) as detail,
        s.eliminated_a + s.eliminated_b as total_eliminated,
        abs(r.balance_a) + abs(r.balance_b) as consolidated_balance
    from per_side as s
    inner join {{ ref('gold_ic_reconciliation') }} as r
        on s.consolidation_group = r.consolidation_group
        and s.fiscal_year = r.fiscal_year
        and s.fiscal_period = r.fiscal_period
        and s.entity_a = r.entity_a
        and s.account_a = r.account_a
        and s.entity_b = r.entity_b
        and s.account_b = r.account_b
    where abs(s.eliminated_a) > abs(r.balance_a) + 0.01
       or abs(s.eliminated_b) > abs(r.balance_b) + 0.01
       or s.eliminated_a * r.balance_a > 0.0001
       or s.eliminated_b * r.balance_b > 0.0001
)

select * from account_check
union all
select * from side_check
