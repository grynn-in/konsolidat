{{
    config(
        engine='MergeTree()',
        order_by='tuple()'
    )
}}

{# PRD-8: Multi-level consolidation hierarchy.

   Single source: epm_staging.consolidation_hierarchy, write-through from the
   konsol Frappe app.

   This model used to fall back to the consolidation_groups seed whenever the
   staging table came back empty ("backward compatibility, flat hierarchy,
   level=1"). Two copies of the same ownership figures, with the model picking
   silently between them and nothing recording which had won — and the copies
   do disagree: the seed carries AMDE at 75%, the staging table at 100%.

   F2 answered the "which is correct" question by deleting the disagreement:
   this model carries NO ownership at all now. It used to expose
   effective_ownership_pct, which held the DIRECT percentage (konsol wrote
   `ownership_pct or 100`) and had no date grain, so it could never expire.
   Ownership is temporal and lives only in Ownership Period; gold_entity_ownership
   resolves it, multiplying the chain through epm_staging.consolidation_ancestry.
   What is left here is what the name always promised: structure.

   The fallback is gone. If the staging table is empty this model now yields
   nothing rather than quietly substituting the seed, and
   tests/assert_staging_not_stale.sql fails the run and names the table.
   See F3/F4 — one metadata path, plus the sync watermark. #}

select
    consolidation_group,
    data_area_id,
    parent_group,
    hierarchy_level,
    path
from {{ source('epm_staging', 'consolidation_hierarchy') }}
where consolidation_group != ''
  and data_area_id != ''
