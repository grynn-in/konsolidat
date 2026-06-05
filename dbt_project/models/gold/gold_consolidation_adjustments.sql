{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-5: Top-side journal adjustments from seed/staging #}
select
    consolidation_group,
    adjustment_type,
    journal_id,
    data_area_id,
    {{ cast_to_uint16('fiscal_year') }} as fiscal_year,
    {{ cast_to_uint8('fiscal_period') }} as fiscal_period,
    main_account,
    debit_amount,
    credit_amount,
    debit_amount - credit_amount as net_amount,
    description,
    posted_by
from {{ ref('consolidation_adjustments') }}
