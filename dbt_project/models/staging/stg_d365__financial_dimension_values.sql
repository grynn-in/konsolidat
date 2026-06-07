{#
    Financial Dimension Values staging model.
    Maps FinancialDimension → FinancialDimensionName.
#}

select
    coalesce(FinancialDimension, '') as FinancialDimensionName,
    coalesce(DimensionValue, '') as DimensionValue,
    coalesce(Description, '') as Description,
    case
        when lower(toString(coalesce(IsSuspended, ''))) in ('yes', 'true', '1') then 1
        else 0
    end as IsSuspended,
    coalesce(ActiveFrom, toDate('1900-01-01')) as ActiveFrom,
    coalesce(ActiveTo, toDate('2099-12-31')) as ActiveTo,
    rowNumberInAllBlocks() as RecId,
    _airbyte_extracted_at,
    _airbyte_raw_id
from {{ source('d365_raw', 'financial_dimension_values') }}
