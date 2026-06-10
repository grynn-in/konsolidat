{#
    D365 F&O trial balance adapter.
    Maps TrialBalanceFiscalYearSnapshots → canonical stg_trial_balance schema.
#}

select
    'd365_fo' as erp_source,
    upper(coalesce(LedgerName, '')) as entity_id,
    coalesce(DimensionValue1, '') as main_account,
    '' as account_name,
    toString(
        case
            when match(coalesce(toString(YearName), ''), '^[0-9]+$') then toUInt16(YearName)
            else toYear(toDate(substring(coalesce(toString(PeriodStartDate), '1970-01-02'), 1, 10)))
        end
    ) as fiscal_year,
    toString(coalesce(OpeningBalance, 0)) as opening_balance,
    toString(coalesce(AmountDebit, 0)) as debit_amount,
    toString(coalesce(AmountCredit, 0)) as credit_amount,
    toString(coalesce(EndingBalance, 0)) as closing_balance,
    '' as currency_code,
    '' as account_type,
    toString(_airbyte_extracted_at) as _loaded_at,
    toString(_airbyte_raw_id) as _raw_id
from {{ source('d365_raw', 'TrialBalanceFiscalYearSnapshots') }}
