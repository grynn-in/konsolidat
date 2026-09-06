{{ config(enabled = 'erpnext' in var('erp_sources', ['d365_fo'])) }}
{#
    Enabled here, not in dbt_project.yml: var() inside a dbt_project.yml
    +enabled config does not see the project's own vars: block and silently
    falls back to the default, while this model body does see it. That
    disagreement disabled these models while the canonical loop still
    ref'd them, which failed the whole dbt parse.
#}
{#
    ERPNext chart of accounts adapter.
    Maps the `Account` doctype → canonical stg_accounts schema.

    ERPNext `root_type` (Asset/Liability/Income/Expense/Equity) maps to the
    canonical account_type; the finer ERPNext `account_type` (Cash, Bank,
    Receivable, …) maps to account_category. account_id is the Account `name`,
    which is exactly what GL Entry.account links to — so gl.main_account joins
    to accounts.account_id within the erpnext source.
#}

select
    'erpnext' as erp_source,
    coalesce(name, '') as account_id,
    coalesce(account_name, '') as account_name,
    coalesce(root_type, '') as account_type,
    coalesce(account_type, '') as account_category,
    '' as debit_credit_default,
    coalesce(company, '') as chart_of_accounts,
    case
        when lower(toString(coalesce(disabled, ''))) in ('yes', 'true', '1') then 1
        else 0
    end as is_suspended,
    _airbyte_extracted_at as _loaded_at,
    _airbyte_raw_id as _raw_id
from {{ source('erpnext_raw', 'account') }}
