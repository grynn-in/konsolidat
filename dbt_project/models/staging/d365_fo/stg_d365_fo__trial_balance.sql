{#
    D365 F&O trial balance adapter.
    Maps TrialBalanceFiscalYearSnapshots → canonical stg_trial_balance schema.
#}

select
    'd365_fo' as erp_source,
    upper(coalesce(LedgerName, '')) as entity_id,
    coalesce(DimensionValue1, '') as main_account,
    '' as account_name,
    case
        when match(coalesce(toString(YearName), ''), '^[0-9]+$') then toUInt16(YearName)
        else toYear(toDate(substring(coalesce(toString(PeriodStartDate), '1970-01-02'), 1, 10)))
    end as fiscal_year,
    coalesce(OpeningBalance, 0) as opening_balance,
    coalesce(AmountDebit, 0) as debit_amount,
    coalesce(AmountCredit, 0) as credit_amount,
    coalesce(EndingBalance, 0) as closing_balance,
    '' as currency_code,
    '' as account_type,
    _airbyte_extracted_at as _loaded_at,
    _airbyte_raw_id as _raw_id
from {{ source('d365_raw', 'trial_balance_fiscal_year_snapshots') }}
