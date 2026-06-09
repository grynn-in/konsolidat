-- PRD-22 Test: All expected consolidation layers must be present in the FCTB
-- At minimum: entity, ic_elimination, cta, topside (layers 1-4 always expected)
select
    'missing_layer' as error,
    expected.layer as missing_layer
from (
    select 'entity' as layer
    union all select 'ic_elimination'
    union all select 'cta'
    union all select 'topside'
) as expected
left join (
    select distinct adjustment_type as layer
    from {{ ref('gold_fully_consolidated_tb') }}
) as actual
    on expected.layer = actual.layer
where actual.layer is null
