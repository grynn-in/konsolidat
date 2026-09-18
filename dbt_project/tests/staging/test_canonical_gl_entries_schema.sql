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
    none at all.

    WHAT THIS TEST DOES AND DOES NOT CATCH — corrected after the PR #222 review.
    An earlier version of this comment claimed that "a column a site declares but
    staging does not produce still fails the compile". That is NOT reachable
    through this test. stg_gl_entries generates its dimension columns from the
    same var('dimensions') this test reads — dim_harmonize_select when
    erp_sources is non-empty, get_dimensions() via empty_relation when it is not
    — so both sides move together and the dimension half of this contract cannot
    fail. A dimension that staging genuinely cannot produce fails inside
    stg_gl_entries itself, before this test is reached.

    What it does still assert is the NON-dimension contract: erp_source,
    record_id, entity_id, posting_date, fiscal_year, fiscal_period, main_account,
    amount, transaction_currency, description, _loaded_at and _raw_id, each named
    explicitly, so dropping or renaming one of those fails the compile. Giving
    the dimension half real teeth would mean asserting against the built
    relation's columns instead of re-deriving them from the var; that is open.
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
