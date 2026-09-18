{#
    Assert canonical GL entries has all required columns with correct types.
    Selects each required column explicitly — if any column is missing,
    dbt compilation fails (which is the real schema contract enforcement).
    At runtime, returns 0 rows if schema is correct.

    konsolidat#220: the dimension columns are SITE-DECLARED, not fixed. konsol
    ships no Dimensions and each site declares its own (konsol#230), so naming
    dim_cost_center / dim_department / dim_business_unit as literals here
    asserted one site's configuration as the contract — and a site declaring
    none (the starting state of every new site) failed this test on a missing
    column. They are therefore rendered through dim_select(), so this contract
    asserts exactly what the site declares: those three, a different set, or
    none at all. The intent above is unchanged — every declared column is still
    selected explicitly by name, so a column a site declares but staging does
    not produce still fails the compile.
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
    {{ dim_select(trailing=true) }}
    _loaded_at,
    _raw_id
from {{ ref('stg_gl_entries') }}
where 1 = 0
