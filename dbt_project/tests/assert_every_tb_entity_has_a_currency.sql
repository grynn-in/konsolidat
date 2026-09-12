{#
    konsol#110 — every entity with trial-balance rows must resolve a currency.

    gold_consolidated_trial_balance takes each entity's accounting currency
    from silver_entity_currencies, so an entity that is in neither konsol's
    Entity master nor the ERP's company master is dropped at that join, and
    one that is in either with no currency set translates at the parity
    fallback. Both are named here instead.

    Replaces assert_tb_submission_entities_consolidatable, the interim guard
    F8 shipped: it checked submitted entities against silver_legal_entities
    alone, because the ERP was then the only place a currency could come from.
    Submitted batches are checked as well as gold_trial_balance, so an entity
    lost between bronze and gold is still caught.

    NOT IN rather than a LEFT JOIN: with join_use_nulls=0 an unmatched row
    fills with '' and `where x is null` never fires.
#}

with tb_entities as (

    select distinct data_area_id from {{ ref('gold_trial_balance') }}
    union distinct
    select distinct data_area_id from {{ ref('bronze_trial_balance_submissions') }}

)

select data_area_id
from tb_entities
where data_area_id not in (
    select data_area_id
    from {{ ref('silver_entity_currencies') }}
    where accounting_currency != ''
)
