{#
    Main Accounts staging model.
    Maps MainAccountType → Type.
#}

select
    coalesce(MainAccountId, '') as MainAccountId,
    coalesce(Name, '') as Name,
    coalesce(MainAccountType, '') as Type,
    coalesce(MainAccountCategory, '') as MainAccountCategory,
    coalesce(DebitCreditDefault, '') as DebitCreditDefault,
    coalesce(ChartOfAccounts, '') as ChartOfAccounts,
    case
        when lower(toString(coalesce(IsSuspended, ''))) in ('yes', 'true', '1') then 1
        else 0
    end as IsSuspended,
    _airbyte_extracted_at,
    _airbyte_raw_id
from {{ source('d365_raw', 'MainAccounts') }}
