{#
    F2: every entity that reaches a consolidated result must have an ownership
    percentage for EVERY link between it and that group, in that period.

    Ownership Period is the only grain now, so a node with no period covering
    the date has no ownership at all — and a chain is only as resolvable as its
    weakest link. gold_entity_ownership reports such a chain as
    has_complete_chain = 0 and effective 0 rather than inventing a number
    (`ownership_pct or 100` is exactly the falsy-zero bug F2 removes). This
    turns that flag into a failed build naming the entity, so the gap is fixed
    by adding a period rather than absorbed as a silent zero.

    `outside_ownership_window` is excluded on purpose: a node whose ownership
    history exists but does not reach this period is one we did not own then —
    before an acquisition, after a disposal (PRD-11/12, both first-class here).
    Consolidation excludes those rows either way, but only an UNRECORDED gap is
    worth failing a build over. Without the distinction an entity acquired in
    2025 failed for every period back to the start of the warehouse.
#}

select
    consolidation_group,
    data_area_id,
    fiscal_year,
    fiscal_period,
    chain_depth
from {{ ref('gold_entity_ownership') }}
where has_complete_chain = 0
  and outside_ownership_window = 0
