{#
    konsol#110 — konsol's Entity master and the ERP must not disagree about the
    currency an entity keeps its books in.

    silver_entity_currencies prefers konsol's answer, so a disagreement would
    otherwise be settled silently: the entity translates from the currency
    konsol names while its ledger is in the one the ERP names, and every
    translated balance is wrong by the cross rate. Fix whichever side is wrong;
    this test does not pick one.
#}

select
    data_area_id,
    governed_currency,
    erp_currency
from {{ ref('silver_entity_currencies') }}
where governed_currency != ''
  and erp_currency != ''
  and governed_currency != erp_currency
