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

{# konsolidat#220: the dimensions are SITE-DECLARED (konsol#230), so this queue
   covers whatever the site declares rather than the three one site happened to
   have. `stg_gl_entries` emits its dimension columns from `var('dimensions')` —
   `dim_harmonize_select` builds the output list, and with `erp_sources: []` the
   `empty_relation` branch types them from `get_dimensions()` — so naming them as
   literals here meant a site declaring a different set (or none) died with
   `UNKNOWN_IDENTIFIER`.

   One limit, narrowed after the PR #222 review: that is true of what
   `stg_gl_entries` PUBLISHES, not of what it reads. With `erp_sources` non-empty
   its `unioned` CTE still selects `dim_cost_center, dim_department,
   dim_business_unit` from each adapter by name, so a site that declares a fourth
   dimension AND runs an ERP connector fails inside `stg_gl_entries` before this
   model is reached. That branch is ERP staging, which konsolidat#221 is removing
   wholesale — so it is not repaired here. #}
with vals as (
    {% if var('dimensions') | length == 0 %}
    {# No declared dimensions means no values to harmonize. A typed, row-less
       select rather than an empty CTE: zero branches would leave `with vals as ()`,
       which is not a SELECT query and ClickHouse rejects outright (Code: 62). Same
       guard, and same reason, as the unpivot macros in reporting_hierarchy_helpers. #}
    select erp_source, entity_id, '' as dimension, '' as source_value
    from {{ ref('stg_gl_entries') }} where 0
    {% else %}
    {% for d in var('dimensions') %}
    select erp_source, entity_id, '{{ d.name }}' as dimension, {{ d.name }} as source_value
    from {{ ref('stg_gl_entries') }} where {{ d.name }} != ''
    {% if not loop.last %}
    union all
    {% endif %}
    {% endfor %}
    {% endif %}
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
