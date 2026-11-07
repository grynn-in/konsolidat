{#
    PRD-8 / F2 / konsol#117: a resolved ownership share is a fraction between 0
    and 1, and the direct links into an entity's node sum to at most 1.

    Was "gold_consolidation_hierarchy.effective_ownership_pct is between 0 and
    100" — a column that held the DIRECT percentage despite its name, and which
    F2 deleted along with the second grain it represented. Until konsol#117 this
    test also asserted effective <= direct: true for one chain, where every
    further link can only shrink the share, and false for a graph, where a
    second path adds to it (shape 1: direct links into D sum to 0.80, the
    effective share at P is 0.68, at A it is 0.60 — but P→A 80% and P→D 20%
    with A→D 100% would give effective 1.0 against a direct 1.0, and three
    paths can put effective above any single direct link).

    What holds for a graph: eff(G, E) <= 1 (konsol refuses issued shares past
    100%, validate refusal 4), and direct_ownership_pct — the sum of the
    DISTINCT links into E's node — is at most 1 for the same reason.
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
   or effective_ownership_pct > 1 + 0.000001
   or direct_ownership_pct < 0
   or direct_ownership_pct > 1 + 0.000001
