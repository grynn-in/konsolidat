{#
    ERPNext GL entries adapter.
    Maps the `GL Entry` doctype → canonical stg_gl_entries schema.

    ERPNext stores each posting as a separate debit OR credit row (one of the
    two is always zero) with analytical dimensions carried as flat columns
    (cost_center, project) rather than D365's LedgerDimensionValuesJson blob.

    record_id: ERPNext `name` is a string ("ACC-GLE-2024-00001"); the canonical
    record_id is numeric (D365 SourceKey) and bronze casts it via toInt64.
    We derive a deterministic Int64 surrogate from the name hash so the column
    is numeric, stable across runs, and UNION-compatible with the D365 adapter.

    amount/is_credit: silver takes abs(amount) and splits debit/credit by the
    is_credit flag, so amount = debit - credit (signed) with is_credit derived
    from the sign reproduces the canonical contract.
#}

select
    'erpnext' as erp_source,
    reinterpretAsInt64(cityHash64(coalesce(name, ''))) as record_id,
    upper(coalesce(company, '')) as entity_id,
    toString(substring(coalesce(toString(posting_date), '1900-01-01'), 1, 10)) as posting_date,
    toInt32OrZero(substring(coalesce(fiscal_year, ''), 1, 4)) as fiscal_year,
    toMonth(toDate(substring(coalesce(toString(posting_date), '1900-01-01'), 1, 10))) as fiscal_period,
    coalesce(account, '') as main_account,
    '' as account_name,
    coalesce(debit, 0) - coalesce(credit, 0) as amount,
    coalesce(debit, 0) - coalesce(credit, 0) as transaction_currency_amount,
    coalesce(account_currency, '') as transaction_currency,
    coalesce(remarks, against, '') as description,
    coalesce(voucher_no, '') as journal_number,
    coalesce(voucher_type, '') as posting_type,
    coalesce(account, '') as ledger_account,
    case
        when coalesce(credit, 0) > coalesce(debit, 0) then 1
        else 0
    end as is_credit,
    coalesce(cost_center, '') as dim_cost_center,
    '' as dim_department,
    coalesce(project, '') as dim_business_unit,
    _airbyte_extracted_at as _loaded_at,
    _airbyte_raw_id as _raw_id
from {{ source('erpnext_raw', 'gl_entry') }}
where coalesce(toString(is_cancelled), '0') not in ('1', 'yes', 'true')
