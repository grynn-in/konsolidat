{#
    PRD-14: an equity-method entity must never appear in an IC elimination.

    Keyed on the ENTITY, not just the group. The previous cut joined on
    (consolidation_group, fiscal_year, fiscal_period) alone, because
    gold_ic_eliminations threw its entities away — so a correct elimination
    between two fully-consolidated entities failed the build as soon as ANY node
    in that group was equity-method in that period. Harmless while every seeded
    row said 'full'; a live false positive now that the method is real data and
    F2 propagates 'equity' to every descendant of an equity-held sub-group.
#}

with equity_entities as (
    select distinct consolidation_group, data_area_id, fiscal_year, fiscal_period
    from {{ ref('gold_entity_ownership') }}
    where consolidation_method = 'equity'
)

select
    ie.rule_id,
    ie.consolidation_group,
    ie.fiscal_year,
    ie.fiscal_period,
    ie.debit_entity,
    ie.credit_entity
from {{ ref('gold_ic_eliminations') }} as ie
inner join equity_entities as ee
    on ie.consolidation_group = ee.consolidation_group
    and ie.fiscal_year = ee.fiscal_year
    and ie.fiscal_period = ee.fiscal_period
{# the entity match sits in WHERE, not ON: ClickHouse accepts only equality
   conjunctions in a JOIN ON, so `in (a, b)` there raises UNSUPPORTED_METHOD. #}
where ee.data_area_id = ie.debit_entity
   or ee.data_area_id = ie.credit_entity
limit 10
