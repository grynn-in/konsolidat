{#
    ERPNext trial balance adapter.
    ERPNext has no trial-balance snapshot doctype (unlike D365's
    TrialBalanceFiscalYearSnapshots), so we derive a TB by aggregating
    `GL Entry` per entity / account / fiscal year → canonical
    stg_trial_balance schema.

    opening_balance is 0 (GL alone carries no opening snapshot); closing_balance
    is the net movement sum(debit - credit). account_name / currency_code /
    account_type are emitted empty to mirror the D365 TB adapter (joined
    downstream from the chart of accounts).

    The fiscal-year parse happens in a CTE so the aggregate GROUP BY references
    the already-typed column rather than re-deriving it — naming the output
    column `fiscal_year` would otherwise shadow the source column and feed an
    Int32 back into substring().
#}

with gl as (
    select
        upper(coalesce(company, '')) as entity_id,
        coalesce(account, '') as main_account,
        toInt32OrZero(substring(coalesce(fiscal_year, ''), 1, 4)) as fiscal_year,
        coalesce(debit, 0) as debit,
        coalesce(credit, 0) as credit,
        _airbyte_extracted_at,
        _airbyte_raw_id
    from {{ source('erpnext_raw', 'gl_entry') }}
    where coalesce(toString(is_cancelled), '0') not in ('1', 'yes', 'true')
)

select
    'erpnext' as erp_source,
    entity_id,
    main_account,
    '' as account_name,
    fiscal_year,
    toFloat64(0) as opening_balance,
    sum(debit) as debit_amount,
    sum(credit) as credit_amount,
    sum(debit - credit) as closing_balance,
    '' as currency_code,
    '' as account_type,
    max(_airbyte_extracted_at) as _loaded_at,
    any(_airbyte_raw_id) as _raw_id
from gl
group by entity_id, main_account, fiscal_year
