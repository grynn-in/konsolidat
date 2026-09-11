{#
    Unmapped dimension values — the "needs harmonization" review queue.

    Surfaces distinct (erp_source, entity_id, dimension, source_value) present
    in canonical GL entries that no published Dimension Mapping covers. Because
    dim_harmonize() passes unmapped values through verbatim, an unmapped value
    appears in stg_gl_entries as its raw source value — i.e. it is neither a
    published canonical_value nor a published source_value for that
    (dimension, erp_source) at that entity. Drives the Dimension Mapping
    review report.

    Entity-aware, mirroring dim_harmonize's two-tier lookup (konsol #111): a
    blank-entity row is the ERP-wide default and covers every entity, while an
    entity-specific row covers only its own. Treating both alike — which is
    what a plain (erp_source, dimension, value) match did — let one mapping
    written for USMF hide the same unmapped cost centre in DEMF, IN10 and every
    other entity, which is exactly the gap this queue exists to show.
#}

with vals as (
    select erp_source, entity_id, 'dim_cost_center' as dimension, dim_cost_center as source_value
    from {{ ref('stg_gl_entries') }} where dim_cost_center != ''
    union all
    select erp_source, entity_id, 'dim_department' as dimension, dim_department as source_value
    from {{ ref('stg_gl_entries') }} where dim_department != ''
    union all
    select erp_source, entity_id, 'dim_business_unit' as dimension, dim_business_unit as source_value
    from {{ ref('stg_gl_entries') }} where dim_business_unit != ''
),

mapped as (
    select erp_source, entity, dimension, canonical_value as v
    from {{ source('epm_staging', 'dimension_mappings') }} where status = 'Published'
    union all
    select erp_source, entity, dimension, source_value as v
    from {{ source('epm_staging', 'dimension_mappings') }} where status = 'Published'
)

select distinct
    vals.erp_source,
    vals.entity_id,
    vals.dimension,
    vals.source_value
from vals
-- covered by an ERP-wide default (entity = '')…
where (vals.erp_source, vals.dimension, vals.source_value) not in (
        select erp_source, dimension, v from mapped where entity = ''
      )
-- …or by a row written for this entity specifically.
  and (vals.erp_source, vals.entity_id, vals.dimension, vals.source_value) not in (
        select erp_source, entity, dimension, v from mapped where entity != ''
      )
