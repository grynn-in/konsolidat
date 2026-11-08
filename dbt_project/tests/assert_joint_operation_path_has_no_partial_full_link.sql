-- IFRS 11.20 / IFRS 10, konsol#117 pair 3 review finding A (refused by name, not computed).
-- A joint operation reached through a partly owned FULL link is carried at the wrong share and with no NCI.
-- P -> S full 80%, S -> J proportional 50%: the weakest link is proportional and the path sum is 0.40, so layer 1
-- posts 40% of J's lines with nci 0. S itself recognises 50% of J's lines (IFRS 11.20) and P consolidates S in
-- full with a 20% minority, so the group should carry 50% of J's lines with NCI = 10% (20% x 50%). Computing
-- that needs an NCI attribution for the intermediary's minority of a joint operation, which is a later pair.
-- Until then the case is refused: the build fails naming the entity. A path of all-100% full links plus
-- proportional links (P -> S full 100, S -> J proportional 50) stays allowed: 0.50 is exactly the operator's share.
select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    data_area_id || ' is a joint operation of ' || consolidation_group
        || ' reached through a partly owned subsidiary: the share of its lines and the minority in it are not computed'
        || ' (konsol#117 pair 3 finding A); hold the joint operation through a wholly owned member, or declare it `none`,'
        || ' until it is built' as sentence
from {{ ref('gold_entity_ownership') }}
where consolidation_method = 'proportional'
  and has_partial_full_link = 1
  and has_complete_chain = 1
