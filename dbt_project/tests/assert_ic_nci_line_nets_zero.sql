{#
    #175 third review L2: the NCI line, summed over both views, is 0 per group
    and period.

    Decision 12 moves the minority's share of an intragroup balance to the NCI
    line twice: the group view's 'nci' entries (the better-owned side's excess
    share) and the NCI view's 'matched' entries (each side's minority share).
    Across the two they cancel: in the full (100%) consolidation an
    intragroup balance leaves nothing on the NCI line. A leg sent anywhere
    else (the difference account, a wrong sign) leaves the line unbalanced.
#}

{# The NCI line is the group's own: its declared NCI Account, or the
   placeholder (konsolidat#208), resolved as gold_ic_eliminations does. #}
with group_nci as (
    {{ ic_group_nci_accounts() }}
),

eliminations as (
    select
        e.consolidation_group as consolidation_group, e.fiscal_year as fiscal_year,
        e.fiscal_period as fiscal_period,
        e.debit_account as debit_account, e.debit_elimination as debit_elimination,
        e.credit_account as credit_account, e.credit_elimination as credit_elimination,
        {{ ic_nci_account_or_placeholder('gn.declared_nci_account') }} as nci_account
    from {{ ref('gold_ic_eliminations') }} as e
    left join group_nci as gn on gn.nci_group = e.consolidation_group
    where e.rule_type = 'balance'
),

legs as (
    select consolidation_group, fiscal_year, fiscal_period, debit_elimination as amount
    from eliminations
    where debit_account = nci_account
    union all
    select consolidation_group, fiscal_year, fiscal_period, credit_elimination
    from eliminations
    where credit_account = nci_account
)

select consolidation_group, fiscal_year, fiscal_period, sum(amount) as nci_line
from legs
group by consolidation_group, fiscal_year, fiscal_period
having abs(sum(amount)) >= 0.01
