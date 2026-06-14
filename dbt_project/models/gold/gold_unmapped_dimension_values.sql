{#
    Unmapped dimension values — the "needs harmonization" review queue.

    Surfaces distinct (erp_source, dimension, source_value) present in
    canonical GL entries that have no published Dimension Mapping. Because
    dim_harmonize() passes unmapped values through verbatim, an unmapped value
    appears in stg_gl_entries as its raw source value — i.e. it is neither a
    published canonical_value nor a published source_value for that
    (dimension, erp_source). Drives the Dimension Mapping review report.
#}

with vals as (
    select erp_source, 'dim_cost_center' as dimension, dim_cost_center as source_value
    from {{ ref('stg_gl_entries') }} where dim_cost_center != ''
    union all
    select erp_source, 'dim_department' as dimension, dim_department as source_value
    from {{ ref('stg_gl_entries') }} where dim_department != ''
    union all
    select erp_source, 'dim_business_unit' as dimension, dim_business_unit as source_value
    from {{ ref('stg_gl_entries') }} where dim_business_unit != ''
),

mapped as (
    select erp_source, dimension, canonical_value as v
    from {{ ref('dimension_mappings') }} where status = 'Published'
    union all
    select erp_source, dimension, source_value as v
    from {{ ref('dimension_mappings') }} where status = 'Published'
)

select distinct
    vals.erp_source,
    vals.dimension,
    vals.source_value
from vals
left anti join mapped
    on vals.erp_source = mapped.erp_source
    and vals.dimension = mapped.dimension
    and vals.source_value = mapped.v
