{#
    PRD-8 / F2: a resolved ownership share must be a fraction between 0 and 1,
    and the effective share can never exceed the direct one.

    Was "gold_consolidation_hierarchy.effective_ownership_pct is between 0 and
    100" — a column that held the DIRECT percentage despite its name, and which
    F2 deleted along with the second grain it represented. The range check moves
    to where ownership now lives, and gains the invariant that makes the chain
    product meaningful: multiplying by another link's share can only shrink it,
    so effective <= direct always. A chain arithmetic bug that inverted or
    dropped a link shows up here.
#}

select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    effective_ownership_pct,
    direct_ownership_pct
from {{ ref('gold_entity_ownership') }}
where effective_ownership_pct < 0
   or effective_ownership_pct > 1
   or direct_ownership_pct < 0
   or direct_ownership_pct > 1
   or effective_ownership_pct > direct_ownership_pct + 0.000001
