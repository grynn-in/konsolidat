{#
    Assert (dimension, erp_source, entity, source_value) is unique among published
    Dimension Mappings — a source value must crosswalk to exactly one canonical
    value per ERP. Returns offending keys (test fails if any rows).
#}

select
    dimension,
    erp_source,
    entity,
    source_value,
    count(*) as n
from {{ source('epm_staging', 'dimension_mappings') }}
where status = 'Published'
group by dimension, erp_source, entity, source_value
having count(*) > 1
