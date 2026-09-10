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

   Which of those is correct is a separate question (see F2 — Consolidation
   Group and Ownership Period both carry ownership at different grains, and
   epm_staging.ownership_periods also says 75%). The defect here is narrower
   and independent of that: whether an ownership percentage came from a live
   table or from a CSV last edited in June should never depend on whether some
   table happened to be populated at build time.

   The fallback is gone. If the staging table is empty this model now yields
   nothing rather than quietly substituting the seed, and
   tests/assert_staging_not_stale.sql fails the run and names the table.
   See F3/F4 — one metadata path, plus the sync watermark. #}

select
    consolidation_group,
    data_area_id,
    parent_group,
    hierarchy_level,
    effective_ownership_pct,
    path
from {{ source('epm_staging', 'consolidation_hierarchy') }}
where consolidation_group != ''
  and data_area_id != ''
