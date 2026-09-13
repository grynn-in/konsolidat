{#
    konsolidat#148 / konsol#159 (decision 1, 13 Sep 2026): elimination never
    exceeds the balance it cancels.

    The engine this replaced joined every ordered entity pair and eliminated
    2.61M against a 2.56M intercompany revenue balance, and 31.5M against a
    14.5M payables balance. This is the invariant that would have caught both.

    Balance eliminations only (unrealized profit is a margin on inventory, not
    a balance being cancelled), in the group view, on each pair's basis
    (decision 14): a balance-sheet account to date, from inception, as the
    group view carries it; a P&L account in the period.

    1. account: per (group, period, account), total elimination does not exceed
       the account's consolidated balance. The balance is taken gross, as the
       sum of |balance| per (entity, partner): a partnerless row or an entity
       with the opposite sign stays on the account after elimination, and a
       net figure would flag a correct elimination of the rest. The difference
       account's and the NCI line's legs are destinations, not eliminations of
       their balances, so they are left out.
    2. side: per pair, each side is eliminated by no more than the group view
       holds of it (group_balance_*), in the direction that reduces it.
       An elimination whose pair key matches no pair is flagged
       (side_without_pair).
#}

{% set pair = "consolidation_group, entity_a, account_a, entity_b, account_b" %}

with eliminations as (
    select * from {{ ref('gold_ic_eliminations') }}
    where rule_type = 'balance' and elimination_view = 'group'
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

destinations as (
    select distinct consolidation_group, ic_difference_account as main_account
    from {{ ref('gold_ic_reconciliation') }}
    where ic_difference_account != ''
    union distinct
    select distinct consolidation_group, '{{ ic_nci_account() }}'
    from {{ ref('gold_ic_reconciliation') }}
),

account_basis as (
    select main_account as basis_account, max(is_balance_sheet) as is_bs
    from {{ ref('gold_consolidated_trial_balance') }}
    group by main_account
),

account_moves as (
    select l.consolidation_group as consolidation_group, l.fiscal_year as fiscal_year,
           l.fiscal_period as fiscal_period, l.leg_account as main_account,
           sum(l.amount) as eliminated_in_period
    from legs as l
    where (l.consolidation_group, l.leg_account) not in (select consolidation_group, main_account from destinations)
    group by l.consolidation_group, l.fiscal_year, l.fiscal_period, l.leg_account
),

account_to_date as (
    select
        m.consolidation_group as consolidation_group, m.fiscal_year as fiscal_year,
        m.fiscal_period as fiscal_period, m.main_account as main_account, ab.is_bs as is_bs,
        m.eliminated_in_period as eliminated_in_period,
        sum(m.eliminated_in_period) over (
            partition by m.consolidation_group, m.main_account
            order by m.fiscal_year, m.fiscal_period
            rows between unbounded preceding and current row
        ) as eliminated_to_date
    from account_moves as m
    inner join account_basis as ab on ab.basis_account = m.main_account
),

slice_moves as (
    select consolidation_group, main_account, data_area_id, partner_data_area_id,
           fiscal_year, fiscal_period, ifNull(toFloat64(sum(group_amount)), 0) as amount
    from {{ ref('gold_consolidated_trial_balance') }}
    group by consolidation_group, main_account, data_area_id, partner_data_area_id, fiscal_year, fiscal_period
),

gross as (
    select consolidation_group, fiscal_year, fiscal_period, main_account, sum(abs(slice_total)) as gross_balance
    from (
        select a.consolidation_group as consolidation_group, a.fiscal_year as fiscal_year,
               a.fiscal_period as fiscal_period, a.main_account as main_account,
               s.data_area_id as data_area_id, s.partner_data_area_id as partner_data_area_id,
               sum(s.amount) as slice_total
        from account_to_date as a
        inner join slice_moves as s
            on s.consolidation_group = a.consolidation_group and s.main_account = a.main_account
        where if(a.is_bs = 1,
                 tuple(s.fiscal_year, s.fiscal_period) <= tuple(a.fiscal_year, a.fiscal_period),
                 s.fiscal_year = a.fiscal_year and s.fiscal_period = a.fiscal_period)
        group by a.consolidation_group, a.fiscal_year, a.fiscal_period, a.main_account,
                 s.data_area_id, s.partner_data_area_id
    )
    group by consolidation_group, fiscal_year, fiscal_period, main_account
),

account_check as (
    select
        'account' as failed_check,
        a.consolidation_group as consolidation_group,
        a.fiscal_year as fiscal_year,
        a.fiscal_period as fiscal_period,
        a.main_account as detail,
        if(a.is_bs = 1, a.eliminated_to_date, a.eliminated_in_period) as total_eliminated,
        g.gross_balance as consolidated_balance
    from account_to_date as a
    left join gross as g
        on g.consolidation_group = a.consolidation_group and g.fiscal_year = a.fiscal_year
        and g.fiscal_period = a.fiscal_period and g.main_account = a.main_account
    where abs(if(a.is_bs = 1, a.eliminated_to_date, a.eliminated_in_period)) > g.gross_balance + 0.01
),

side_moves as (
    select
        consolidation_group, fiscal_year, fiscal_period, entity_a, account_a, entity_b, account_b,
        sumIf(amount, leg_entity = entity_a and leg_account = account_a) as eliminated_a,
        sumIf(amount, leg_entity = entity_b and leg_account = account_b) as eliminated_b
    from legs
    group by consolidation_group, fiscal_year, fiscal_period, entity_a, account_a, entity_b, account_b
),

sides as (
    select
        s.consolidation_group as consolidation_group, s.fiscal_year as fiscal_year,
        s.fiscal_period as fiscal_period, s.entity_a as entity_a, s.account_a as account_a,
        s.entity_b as entity_b, s.account_b as account_b,
        {# LEFT, so an elimination whose pair key matches no pair is flagged
           rather than dropped. join_use_nulls=0: a miss comes back as '' and 0. #}
        r.consolidation_group = '' as pair_missing,
        r.basis as basis,
        r.group_balance_a as group_balance_a,
        r.group_balance_b as group_balance_b,
        s.eliminated_a as eliminated_a,
        s.eliminated_b as eliminated_b,
        sum(s.eliminated_a) over (
            partition by s.consolidation_group, s.entity_a, s.account_a, s.entity_b, s.account_b
            order by s.fiscal_year, s.fiscal_period rows between unbounded preceding and current row
        ) as eliminated_a_to_date,
        sum(s.eliminated_b) over (
            partition by s.consolidation_group, s.entity_a, s.account_a, s.entity_b, s.account_b
            order by s.fiscal_year, s.fiscal_period rows between unbounded preceding and current row
        ) as eliminated_b_to_date
    from side_moves as s
    left join {{ ref('gold_ic_reconciliation') }} as r
        on s.consolidation_group = r.consolidation_group
        and s.fiscal_year = r.fiscal_year
        and s.fiscal_period = r.fiscal_period
        and s.entity_a = r.entity_a
        and s.account_a = r.account_a
        and s.entity_b = r.entity_b
        and s.account_b = r.account_b
),

side_check as (
    select
        if(pair_missing, 'side_without_pair', 'side') as failed_check,
        consolidation_group,
        fiscal_year,
        fiscal_period,
        concat(entity_a, '/', account_a, ' <> ', entity_b, '/', account_b) as detail,
        if(basis = 'balance', eliminated_a_to_date + eliminated_b_to_date, eliminated_a + eliminated_b) as total_eliminated,
        abs(group_balance_a) + abs(group_balance_b) as consolidated_balance
    from sides
    where pair_missing
       or abs(if(basis = 'balance', eliminated_a_to_date, eliminated_a)) > abs(group_balance_a) + 0.01
       or abs(if(basis = 'balance', eliminated_b_to_date, eliminated_b)) > abs(group_balance_b) + 0.01
       or if(basis = 'balance', eliminated_a_to_date, eliminated_a) * group_balance_a > 0.0001
       or if(basis = 'balance', eliminated_b_to_date, eliminated_b) * group_balance_b > 0.0001
)

select * from account_check
union all
select * from side_check
