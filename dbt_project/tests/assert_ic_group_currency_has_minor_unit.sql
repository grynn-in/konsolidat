-- konsolidat#395, option B (Deepak Pai, 27 Nov 2026; rejected: A, a fixed 4 places, and C,
-- summing in Decimal). A group with intercompany eliminations must have a currency with an ISO
-- minor unit.
--
-- gold_fully_consolidated_tb decides whether a side's slices cover its elimination leg by rounding
-- both to the group currency's minor unit (ic_leg_covered, macros/materiality.sql), following the
-- 18 Sep 2026 decision that materiality follows the currency's minor unit (konsolidat#209). The
-- minor unit comes from group_minor_units(): the group's reporting currency on its root row
-- (data_area_id '') and the currencies row konsol writes from ISO Currency.minor_unit.
--
-- A group with no minor unit has no scale to round to. The model never judges it at a default:
-- join_use_nulls=0 would read a missing minor unit as 0, the JPY scale, so the model reads
-- has_minor_unit instead, and with it 0 every leg of the group goes whole on the blank slice. That
-- is a loss of detail, so this test refuses the build and names the group and the currency (blank
-- when the root row declares none, or when the group has no root row).
--
-- Error severity: without it the loss of slice detail would be silent.
with ic_groups as (
    select distinct consolidation_group from {{ ref('gold_ic_eliminations') }}
),

roots as (
    select consolidation_group, any(reporting_currency) as currency
    from {{ source('epm_gold', 'consolidation_groups') }}
    where data_area_id = ''
    group by consolidation_group
)

-- the LEFT JOIN only labels a refused group: a miss is a group with no root row, and '' is what it
-- declares. The refusal itself is the NOT IN.
select
    g.consolidation_group as consolidation_group,
    r.currency as currency,
    'the group currency has no ISO minor unit: intercompany coverage cannot be decided' as reason
from ic_groups as g
left join roots as r on r.consolidation_group = g.consolidation_group
where g.consolidation_group not in (select consolidation_group from {{ group_minor_units() }})
