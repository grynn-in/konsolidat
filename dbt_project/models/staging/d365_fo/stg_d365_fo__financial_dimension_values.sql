{#
    Financial Dimension Values staging model.
    Maps FinancialDimension → FinancialDimensionName.
#}

select
    coalesce(FinancialDimension, '') as FinancialDimensionName,
    coalesce(DimensionValue, '') as DimensionValue,
    coalesce(Description, '') as Description,
    case
        when lower(coalesce(toString(IsSuspended), '')) in ('yes', 'true', '1') then 1
        else 0
    end as IsSuspended,
    toDate(substring(coalesce(toString(ActiveFrom), '1900-01-01'), 1, 10)) as ActiveFrom,
    toDate(substring(coalesce(toString(ActiveTo), '2099-12-31'), 1, 10)) as ActiveTo,
    rowNumberInAllBlocks() as RecId,
    _airbyte_extracted_at,
    _airbyte_raw_id
from {{ source('d365_raw', 'FinancialDimensionValues') }}
