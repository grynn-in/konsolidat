{#
    PRD-14: an equity-method entity must never appear in an IC elimination.

    Keyed on the ENTITY, not just the group. The previous cut joined on
    (consolidation_group, fiscal_year, fiscal_period) alone, because
    gold_ic_eliminations threw its entities away — so a correct elimination
    between two fully-consolidated entities failed the build as soon as ANY node
    in that group was equity-method in that period. Harmless while every seeded
    row said 'full'; a live false positive now that the method is real data and
    F2 propagates 'equity' to every descendant of an equity-held sub-group.

    One exception (#175 third review M1): the period a balance-sheet pair
    leaves the group because a side moved to equity, the pair's 'left' row
    reverses everything eliminated while that side was fully consolidated.
    Those entries touch the equity-method entity in its first equity period,
    and only undo earlier ones: the row's values are 0, so nothing new is
    eliminated. assert_ic_pair_left_is_reversed checks they are complete.
#}

with equity_entities as (
    select distinct consolidation_group, data_area_id, fiscal_year, fiscal_period
    from {{ ref('gold_entity_ownership') }}
    where consolidation_method = 'equity'
),

left_rows as (
    select consolidation_group, fiscal_year, fiscal_period, entity_a, account_a, entity_b, account_b,
           toUInt8(1) as is_left
    from {{ ref('gold_ic_reconciliation') }}
    where pair_event = 'left'
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
{# join_use_nulls=0: an entry of a pair with no 'left' row that period gets 0 #}
left join left_rows as lr
    on lr.consolidation_group = ie.consolidation_group
    and lr.fiscal_year = ie.fiscal_year
    and lr.fiscal_period = ie.fiscal_period
    and lr.entity_a = ie.entity_a and lr.account_a = ie.account_a
    and lr.entity_b = ie.entity_b and lr.account_b = ie.account_b
{# the entity match sits in WHERE, not ON: ClickHouse accepts only equality
   conjunctions in a JOIN ON, so `in (a, b)` there raises UNSUPPORTED_METHOD. #}
where (ee.data_area_id = ie.debit_entity
       or ee.data_area_id = ie.credit_entity)
  and lr.is_left = 0
limit 10
