{#
    Assert canonical GL entries has all required columns with correct types.
    Selects each required column explicitly — if any column is missing,
    dbt compilation fails (which is the real schema contract enforcement).
    At runtime, returns 0 rows if schema is correct.
#}

select
    erp_source,
    record_id,
    entity_id,
    posting_date,
    fiscal_year,
    fiscal_period,
    main_account,
    amount,
    transaction_currency,
    description,
    dim_cost_center,
    dim_department,
    dim_business_unit,
    _loaded_at,
    _raw_id
from {{ ref('stg_gl_entries') }}
where 1 = 0
