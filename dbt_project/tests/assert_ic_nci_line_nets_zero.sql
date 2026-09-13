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

{% set nci = ic_nci_account() %}

with legs as (
    select consolidation_group, fiscal_year, fiscal_period, debit_elimination as amount
    from {{ ref('gold_ic_eliminations') }}
    where rule_type = 'balance' and debit_account = '{{ nci }}'
    union all
    select consolidation_group, fiscal_year, fiscal_period, credit_elimination
    from {{ ref('gold_ic_eliminations') }}
    where rule_type = 'balance' and credit_account = '{{ nci }}'
)

select consolidation_group, fiscal_year, fiscal_period, sum(amount) as nci_line
from legs
group by consolidation_group, fiscal_year, fiscal_period
having abs(sum(amount)) >= 0.01
