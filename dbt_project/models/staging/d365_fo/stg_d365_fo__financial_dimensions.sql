{#
    Financial Dimensions staging model.
    Maps DimensionAttributes → financial_dimensions.
    UseValuesFrom → Description, ReportColumnName → BackingEntityType.
#}

select
    coalesce(DimensionName, '') as DimensionName,
    coalesce(UseValuesFrom, '') as Description,
    coalesce(ReportColumnName, '') as BackingEntityType,
    1 as IsActive,
    rowNumberInAllBlocks() as RecId,
    _airbyte_extracted_at,
    _airbyte_raw_id
from {{ source('d365_raw', 'DimensionAttributes') }}
