-- PRD-22 Test: All expected consolidation layers must be present in the FCTB
-- At minimum: entity, ic_elimination, cta, topside (layers 1-4 always expected)
--
-- konsolidat#238 / #249: NOT IN, not a LEFT JOIN. adjustment_type is a String, and
-- under join_use_nulls = 0 (the server default; a singular test carries no settings
-- clause) an unmatched LEFT JOIN fills it with '' rather than NULL, so the former
-- `where actual.layer is null` matched nothing and this test could never fail.
-- test_fixtures/assert_all_layers_present.must_flag.sql holds the entity layer only
-- and must flag the other three.
select
    'missing_layer' as error,
    expected.layer as missing_layer
from (
    select 'entity' as layer
    union all select 'ic_elimination'
    union all select 'cta'
    union all select 'topside'
) as expected
where expected.layer not in (
    select distinct adjustment_type
    from {{ ref('gold_fully_consolidated_tb') }}
)
