{#
    konsol#159: each intercompany account belongs to one pair. An account
    paired with two counterparts would have one side matched twice, which is
    the over-elimination konsolidat#148 removed. konsol refuses such a row;
    this catches one that reached the warehouse anyway (ic_account_map() then
    keeps just one counterpart).
#}

select
    account,
    count(distinct cp) as counterparts,
    groupUniqArray(cp) as paired_with
from (
    select
        main_account as account,
        if(counterpart_account = '', main_account, counterpart_account) as cp
    from {{ source('epm_staging', 'intercompany_accounts') }}
    where status = 'Published'
    union all
    select counterpart_account as account, main_account as cp
    from {{ source('epm_staging', 'intercompany_accounts') }}
    where status = 'Published'
      and counterpart_account != ''
      and counterpart_account != main_account
)
group by account
having count(distinct cp) > 1
