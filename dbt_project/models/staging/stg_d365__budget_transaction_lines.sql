{#
    Budget Transaction Lines staging model.
    Each row in BudgetRegisterEntries represents a line.
    Parses DimensionDisplayValue for MainAccount (first segment) and dimensions.
    Links to header via EntryNumber → sequential RecId.
#}

with entries as (
    select
        *,
        dense_rank() over (order by EntryNumber) as header_recid
    from {{ source('d365_raw', 'budget_register_entries') }}
)

select
    rowNumberInAllBlocks() as RecId,
    header_recid as BudgetRegisterEntry,
    Date,
    splitByChar('-', coalesce(DimensionDisplayValue, ''))[1] as MainAccount,
    coalesce(AccountingCurrencyAmount, 0) as AccountingCurrencyAmount,
    coalesce(TransactionCurrencyAmount, 0) as TransactionCurrencyAmount,
    coalesce(CurrencyCode, '') as TransactionCurrency,
    -- Use dedicated fields; clean up error messages
    case
        when coalesce(BusinessUnit, '') like '%does not exist%' then ''
        else coalesce(BusinessUnit, '')
    end as CostCenter,
    case
        when coalesce(Department, '') like '%does not exist%' then ''
        else coalesce(Department, '')
    end as Department,
    case
        when lower(toString(coalesce(IncludeInCashFlowForecast, ''))) in ('yes', 'true', '1') then 1
        else 0
    end as IncludeInCashFlowForecast,
    _airbyte_extracted_at,
    _airbyte_raw_id
from entries
