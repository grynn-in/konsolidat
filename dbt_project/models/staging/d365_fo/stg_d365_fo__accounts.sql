{#
    D365 F&O chart of accounts adapter.
    Maps MainAccounts → canonical stg_accounts schema.
#}

select
    'd365_fo' as erp_source,
    coalesce(MainAccountId, '') as account_id,
    coalesce(Name, '') as account_name,
    coalesce(MainAccountType, '') as account_type,
    coalesce(MainAccountCategory, '') as account_category,
    coalesce(DebitCreditDefault, '') as debit_credit_default,
    coalesce(ChartOfAccounts, '') as chart_of_accounts,
    case
        when lower(toString(coalesce(IsSuspended, ''))) in ('yes', 'true', '1') then 1
        else 0
    end as is_suspended,
    _airbyte_extracted_at as _loaded_at,
    _airbyte_raw_id as _raw_id
from {{ source('d365_raw', 'main_accounts') }}
