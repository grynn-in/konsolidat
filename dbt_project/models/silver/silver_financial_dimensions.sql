{{
    config(
        engine='MergeTree()',
        order_by='(dimension_name, dimension_value)'
    )
}}

select
    dv.dimension_name,
    dv.dimension_value,
    dv.description as value_description,
    d.description as dimension_description,
    dv.is_suspended,
    dv.active_from,
    dv.active_to,
    d.is_active as dimension_is_active
from {{ ref('bronze_financial_dimension_values') }} as dv
left join {{ ref('bronze_financial_dimensions') }} as d
    on dv.dimension_name = d.dimension_name
where dv.is_suspended = 0
