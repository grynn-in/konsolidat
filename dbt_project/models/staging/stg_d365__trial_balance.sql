{#
    Trial Balance staging model.
    Maps TrialBalanceFiscalYearSnapshots fields:
      LedgerName → dataAreaId, DimensionValue1 → MainAccount,
      AmountDebit → DebitAmount, AmountCredit → CreditAmount,
      EndingBalance → ClosingBalance.
#}

select
    upper(coalesce(LedgerName, '')) as dataAreaId,
    coalesce(DimensionValue1, '') as MainAccount,
    '' as MainAccountName,
    case
        when match(coalesce(YearName, ''), '^[0-9]+$') then toUInt16(YearName)
        else toYear(coalesce(PeriodStartDate, toDate('1970-01-02')))
    end as FiscalYear,
    coalesce(OpeningBalance, 0) as OpeningBalance,
    coalesce(AmountDebit, 0) as DebitAmount,
    coalesce(AmountCredit, 0) as CreditAmount,
    coalesce(EndingBalance, 0) as ClosingBalance,
    '' as CurrencyCode,
    '' as AccountType,
    _airbyte_extracted_at,
    _airbyte_raw_id
from {{ source('d365_raw', 'trial_balance_fiscal_year_snapshots') }}
