{#
    D365 F&O budget entries adapter.
    Each row in BudgetRegisterEntries is a line item.
    Parses DimensionDisplayValue for MainAccount (first segment).
    Links to header via EntryNumber → sequential dense_rank RecId.
    Output matches canonical stg_budget_entries schema.
#}

with lines as (
    select
        *,
        dense_rank() over (order by EntryNumber) as header_recid
    from {{ source('d365_raw', 'BudgetRegisterEntries') }}
)

select
    'd365_fo' as erp_source,
    rowNumberInAllBlocks() as record_id,
    upper(coalesce(lines.dataAreaId, lines.LegalEntityId, '')) as entity_id,
    toString(substring(coalesce(toString(lines.Date), '1900-01-01'), 1, 10)) as posting_date,
    splitByChar('-', coalesce(lines.DimensionDisplayValue, ''))[1] as main_account,
    coalesce(lines.AccountingCurrencyAmount, 0) as amount,
    coalesce(lines.TransactionCurrencyAmount, 0) as transaction_amount,
    coalesce(lines.CurrencyCode, '') as transaction_currency,
    coalesce(lines.BudgetModelId, '') as budget_model,
    coalesce(lines.Status, 'Completed') as budget_status,
    case
        when coalesce(lines.BusinessUnit, '') like '%does not exist%' then ''
        else coalesce(lines.BusinessUnit, '')
    end as dim_cost_center,
    case
        when coalesce(lines.Department, '') like '%does not exist%' then ''
        else coalesce(lines.Department, '')
    end as dim_department,
    lines._airbyte_extracted_at as _loaded_at,
    lines._airbyte_raw_id as _raw_id,
    -- D365-specific fields needed by bronze (backward compat)
    lines.header_recid as budget_register_entry_recid,
    case
        when lower(toString(coalesce(lines.IncludeInCashFlowForecast, ''))) in ('yes', 'true', '1') then 1
        else 0
    end as include_in_cash_flow
from lines
