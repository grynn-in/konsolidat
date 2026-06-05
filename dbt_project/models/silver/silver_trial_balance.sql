{{
    config(
        engine='MergeTree()',
        order_by='(data_area_id, fiscal_year, main_account)'
    )
}}

select
    data_area_id,
    main_account,
    main_account_name,
    fiscal_year,
    opening_balance,
    debit_amount,
    credit_amount,
    closing_balance,
    currency_code,
    account_type,
    -- Validation: closing = opening + debit - credit
    opening_balance + debit_amount - credit_amount as calculated_closing
from {{ ref('bronze_trial_balance_snapshot') }}
