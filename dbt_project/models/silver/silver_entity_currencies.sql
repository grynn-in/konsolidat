{{
    config(
        engine='MergeTree()',
        order_by='(data_area_id)'
    )
}}

{# konsol#110 — which currency each entity keeps its books in. The one answer.

   Two sources:
   * epm_staging.entities — konsol's Entity master (functional_currency),
     written through on every save. The governed answer, and the only one an
     entity with no ERP connector has.
   * silver_legal_entities — the ERP's company master. The fallback for an
     entity whose functional currency nobody has entered in konsol yet.

   konsol wins when both are set. assert_entity_currency_sources_agree fails
   the build when they differ, because silently overriding the ERP is how a
   subsidiary gets translated from the wrong currency.

   UNION + GROUP BY, not a join, on purpose: with join_use_nulls=0 an unmatched
   LEFT JOIN fills a String with '' rather than NULL, so coalesce(konsol, erp)
   returns '' and never reaches the ERP value. anyIf over no matching rows
   yields '' too — which is why each side is filtered to non-empty. #}

with candidates as (

    select
        data_area_id,
        accounting_currency,
        'konsol' as origin
    from {{ source('epm_staging', 'entities') }}
    where is_group = 0

    union all

    select
        data_area as data_area_id,
        accounting_currency,
        'erp' as origin
    from {{ ref('silver_legal_entities') }}

),

by_source as (

    select
        data_area_id,
        anyIf(accounting_currency, origin = 'konsol' and accounting_currency != '') as governed_currency,
        anyIf(accounting_currency, origin = 'erp' and accounting_currency != '') as erp_currency,
        countIf(origin = 'konsol') > 0 as in_konsol,
        countIf(origin = 'erp') > 0 as in_erp
    from candidates
    group by data_area_id

)

{# Resolved here, one step out: naming it accounting_currency inside by_source
   would shadow the column its own anyIf reads (ClickHouse: CYCLIC_ALIASES). #}
select
    data_area_id,
    if(governed_currency != '', governed_currency, erp_currency) as accounting_currency,
    multiIf(governed_currency != '', 'konsol', erp_currency != '', 'erp', '') as currency_source,
    governed_currency,
    erp_currency,
    in_konsol,
    in_erp
from by_source
